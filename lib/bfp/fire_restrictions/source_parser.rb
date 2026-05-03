require "date"
require_relative "auto_review_policy"

module BFP
  module FireRestrictions
    class SourceParser
      PRIMARY_MODEL_ID = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
      ESCALATION_MODEL_ID = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"

      def initialize(parser_client: BFP::LLM::ParserClient.build, validator: ObservationValidator.new, auto_review_policy: AutoReviewPolicy.new)
        @parser_client = parser_client
        @validator = validator
        @auto_review_policy = auto_review_policy
      end

      def parse_fetch(fetch)
        fetch = SourceFetch[fetch] unless fetch.is_a?(SourceFetch)
        return unless fetch

        source = fetch.restriction_source
        land_unit = source.land_unit

        unless fetch.source_document
          return create_unknown_observation(fetch, source, land_unit, ["Fetch did not produce a source document."])
        end

        document = fetch.source_document
        extraction = extract_document(document, fetch, source)
        if extraction[:extraction_status] == "needs_review"
          return create_unknown_observation(fetch, source, land_unit, [extraction[:extraction_error]].compact)
        end

        result = parse_result(document.extracted_text.to_s, source, land_unit)
        result = apply_structural_overrides(result, document.extracted_text.to_s, source)
        validation = @validator.validate(result, source: source, extracted_text: document.extracted_text.to_s)

        if should_escalate?(result, validation, document.extracted_text.to_s, source, land_unit)
          escalation_result = parse_result(document.extracted_text.to_s, source, land_unit, escalation: true)
          unless parser_failure?(escalation_result)
            result = escalation_result
            validation = @validator.validate(result, source: source, extracted_text: document.extracted_text.to_s)
          end
        end

        observation = create_observation(fetch, source, land_unit, result, validation)
        Resolver.new.resolve(land_unit)
        observation
      end

      private

      def extract_document(document, fetch, source)
        extraction = extractor_for(document.content_type, fetch.final_url, source).extract(
          document.body.to_s,
          final_url: fetch.final_url || source.url
        )

        document.set(
          title: extraction[:title],
          canonical_url: extraction[:canonical_url],
          modified_at: extraction[:modified_at],
          extraction_status: extraction[:extraction_status],
          extraction_error: extraction[:extraction_error],
          extracted_text: extraction[:extracted_text],
          metadata_json: Jsonb.wrap((document.metadata_json || {}).merge(extraction[:metadata_json] || {})),
          updated_at: Time.now
        )
        document.save
        extraction
      end

      def extractor_for(content_type, final_url, source)
        return JsonExtractor.new if source.source_type == "arcgis_feature_layer"
        return Extractors::PdfExtractor.new if content_type.to_s.include?("pdf") || final_url.to_s.end_with?(".pdf")

        Extractors::HtmlExtractor.new
      end

      def parse_result(text, source, land_unit, escalation: false)
        return ArcgisAdapter.new.parse(text: text, source: source, land_unit: land_unit) if source.source_type == "arcgis_feature_layer"
        return parse_disabled_result unless llm_parse_enabled?

        model_id = escalation ? escalation_model_id : primary_model_id
        @parser_client.parse(text: text, source: source, land_unit: land_unit, model_id: model_id)
      rescue => error
        parse_error_result(error, model_id)
      end

      def llm_parse_enabled?
        ENV.fetch("LLM_PARSE_ENABLED", "false") == "true" || BFP.env == "test"
      end

      def llm_escalation_enabled?
        ENV.fetch("LLM_ESCALATION_ENABLED", "false") == "true"
      end

      def primary_model_id
        ENV.fetch("BEDROCK_PRIMARY_MODEL_ID", PRIMARY_MODEL_ID)
      end

      def escalation_model_id
        ENV.fetch("BEDROCK_ESCALATION_MODEL_ID", ESCALATION_MODEL_ID)
      end

      def should_escalate?(result, validation, text, source, land_unit)
        return false unless llm_escalation_enabled?
        return false if source.source_type == "arcgis_feature_layer"
        return false if parser_failure?(result)

        result["confidence"].to_f < 0.7 ||
          !validation.valid? ||
          ambiguous_restriction_language?(result, text) ||
          multiple_overlapping_orders?(text) ||
          conflicts_with_recent_observation?(result, land_unit, source)
      end

      def ambiguous_restriction_language?(result, text)
        result["status"].to_s == "unknown" && text.match?(/restriction|campfire|public use|forest order|prohibit/i)
      end

      def multiple_overlapping_orders?(text)
        text.scan(/forest order|order number|order no\.?|order #/i).length > 1
      end

      def conflicts_with_recent_observation?(result, land_unit, source)
        status = result["status"].to_s
        return false if status == "unknown"

        recent = RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: %w[accepted auto_accepted])
          .exclude(restriction_source_id: source.id)
          .exclude(status: "unknown")
          .where { created_at > Time.now - (14 * 24 * 60 * 60) }
          .reverse(:created_at)
          .first

        recent && recent.status != status
      end

      def create_observation(fetch, source, land_unit, result, validation)
        reasons = Array(result["needs_review_reasons"]) + validation.errors
        review_status = review_status_for(
          source,
          result,
          validation,
          reasons,
          extracted_text: fetch.source_document&.extracted_text.to_s
        )

        RestrictionObservation.create(
          land_unit_id: land_unit.id,
          restriction_source_id: source.id,
          source_fetch_id: fetch.id,
          status: clean_enum(result["status"], "unknown"),
          campfire_policy: clean_enum(result["campfire_policy"], "unknown"),
          fire_danger_rating: result["fire_danger_rating"],
          ifpl_level: result["ifpl_level"],
          effective_start: parse_date(result["effective_start"]),
          effective_end: parse_date(result["effective_end"]),
          order_number: result["order_number"],
          affected_area: result["affected_area"],
          geometry_json: Jsonb.wrap(result["geometry_json"]),
          summary: result["summary"],
          evidence_quotes: Jsonb.wrap(Array(result["evidence_quotes"])),
          confidence: result["confidence"].to_f,
          review_status: review_status,
          parser_provider: result["parser_provider"],
          parser_model_id: result["parser_model_id"],
          parser_version: "2026-05-03",
          source_url: fetch.source_document&.canonical_url || fetch.final_url || source.url,
          source_title: fetch.source_document&.title || source.name,
          needs_review_reasons: Jsonb.wrap(reasons),
          validation_errors: Jsonb.wrap(validation.errors),
          raw_output: Jsonb.wrap(result)
        )
      end

      def create_unknown_observation(fetch, source, land_unit, reasons)
        validation = ObservationValidator::Result.new(valid?: false, errors: reasons)
        result = parse_disabled_result.merge("needs_review_reasons" => reasons)
        create_observation(fetch, source, land_unit, result, validation)
      end

      def review_status_for(source, result, validation, reasons, extracted_text:)
        @auto_review_policy.review_status_for_result(
          source: source,
          result: result,
          validation: validation,
          reasons: reasons,
          extracted_text: extracted_text
        )
      end

      def parse_date(value)
        return if value.to_s.strip.empty?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def clean_enum(value, fallback)
        value.to_s.empty? ? fallback : value.to_s
      end

      def parse_disabled_result
        {
          "status" => "unknown",
          "campfire_policy" => "unknown",
          "fire_danger_rating" => nil,
          "ifpl_level" => nil,
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => nil,
          "summary" => nil,
          "evidence_quotes" => [],
          "confidence" => 0.0,
          "needs_review_reasons" => ["LLM parsing is disabled or unavailable."],
          "parser_provider" => ENV.fetch("LLM_PROVIDER", "bedrock"),
          "parser_model_id" => nil
        }
      end

      def apply_structural_overrides(result, text, source)
        result = result.dup
        apply_current_pur_override(result, text, source)
      end

      def apply_current_pur_override(result, text, source)
        return result unless source.respond_to?(:authority)
        return result unless source.authority == "official_usfs"
        return result unless text.match?(/PUR:\s*Seasonal Restrictions/i)
        return result unless text.match?(/Fire Danger:\s*LOW/i)
        return result unless text.match?(/IFPL:\s*I/i)

        result.merge(
          "status" => "advisory",
          "campfire_policy" => "allowed",
          "fire_danger_rating" => "LOW",
          "ifpl_level" => "I",
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => nil,
          "summary" => "Current public-use restrictions are in Seasonal Restrictions/Phase A with LOW fire danger and IFPL I.",
          "evidence_quotes" => ["Fire Danger: LOW", "IFPL: I", "PUR: Seasonal Restrictions"],
          "confidence" => [result["confidence"].to_f, 0.9].max,
          "needs_review_reasons" => Array(result["needs_review_reasons"]).reject { |reason| ignorable_current_pur_reason?(reason) }
        )
      end

      def ignorable_current_pur_reason?(reason)
        reason.to_s.match?(/Seasonal Restrictions|Phase A|campfire policy|effective dates|template|informational page/i)
      end

      def parse_error_result(error, model_id)
        parse_disabled_result.merge(
          "needs_review_reasons" => ["LLM parsing failed: #{error.class}: #{error.message}"],
          "parser_model_id" => model_id
        )
      end

      def parser_failure?(result)
        Array(result["needs_review_reasons"]).any? { |reason| reason.to_s.start_with?("LLM parsing failed:") }
      end

      class JsonExtractor
        def extract(body, final_url: nil)
          {
            title: nil,
            canonical_url: final_url,
            extracted_text: body.to_s,
            extraction_status: "ok",
            metadata_json: Jsonb.wrap({})
          }
        end
      end
    end
  end
end
