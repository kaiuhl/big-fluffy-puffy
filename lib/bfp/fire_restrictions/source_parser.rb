require "date"
require "digest"
require_relative "auto_review_policy"
require_relative "extractors/nps_alerts_extractor"
require_relative "localized_rule_validator"
require_relative "models"

module BFP
  module FireRestrictions
    class SourceParser
      PRIMARY_MODEL_ID = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
      ESCALATION_MODEL_ID = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
      PARTIAL_NPS_FIRE_RULE_SOURCES = %w[
        north-cascades-wilderness-trip-planner
        olympic-national-park-wilderness-regulations
      ].freeze
      DEVELOPED_SITE_ONLY_NPS_FIRE_RULE_SOURCES = %w[
        lassen-volcanic-fire-regulations
      ].freeze
      NPS_BACKCOUNTRY_FIRE_RESTRICTIONS = {
        "mount-rainier-wilderness-regulations" => {
          pattern: /following items or activities are prohibited on the trails and in the backcountry of Mount Rainier National Park:\s*Fire \(white gas, iso-butane cartridge, alcohol stoves are okay\. No bio-fuel stoves; i\.e\., those that burn twigs, sticks, cones, etc\.\)/i,
          evidence_quote: "following items or activities are prohibited on the trails and in the backcountry of Mount Rainier National Park: Fire (white gas, iso-butane cartridge, alcohol stoves are okay. No bio-fuel stoves; i.e., those that burn twigs, sticks, cones, etc.)",
          affected_area: "trails and backcountry",
          summary: "Fires are prohibited on Mount Rainier trails and in the backcountry; white gas, iso-butane cartridge, and alcohol stoves are allowed."
        },
        "crater-lake-backcountry-faq" => {
          pattern: /Campfires are prohibited in the park's backcountry/i,
          evidence_quote: "Campfires are prohibited in the park's backcountry.",
          affected_area: "park backcountry",
          summary: "Campfires are prohibited in Crater Lake's backcountry; fuel-canister and liquid-fuel camp stoves are permitted."
        },
        "north-cascades-wilderness-trip-planner" => {
          pattern: /See the table below for information on group size limitation for each backcountry camp, food storage requirements, and campfire rules.*No Campfires/im,
          evidence_quote: "Fisher Pit Canister 4,4,4 4 No Campfires, Bear Canister Required",
          affected_area: "listed backcountry camps and cross-country zones",
          summary: "Some North Cascades backcountry camps and cross-country zones prohibit campfires; the wilderness trip planner lists campfire rules by camp."
        },
        "olympic-national-park-wilderness-regulations" => {
          pattern: /Campfires and wood-burning camp stoves are allowed below 3,500 feet only.*Campfires and wood-burning camp stoves are not allowed on the coast between the headland at Wedding Rocks and the headland north of Yellow Banks/im,
          evidence_quote: "Campfires and wood-burning camp stoves are not allowed on the coast between the headland at Wedding Rocks and the headland north of Yellow Banks.",
          affected_area: "wilderness above 3,500 feet and the coast between Wedding Rocks and Yellow Banks",
          summary: "Olympic allows campfires and wood-burning camp stoves below 3,500 feet only, with an additional coastal prohibition between Wedding Rocks and Yellow Banks."
        },
        "lassen-volcanic-fire-regulations" => {
          pattern: /Fires are only allowed in park-provided grills or fire rings in established frontcountry campgrounds and day use areas.*Fires are not permitted in any other area of the park, including backcountry and wilderness areas/im,
          evidence_quote: "Fires are not permitted in any other area of the park, including backcountry and wilderness areas.",
          affected_area: "outside established frontcountry campgrounds and day-use areas",
          summary: "Fires are allowed only in park-provided grills or fire rings in established frontcountry campgrounds and day-use areas; liquid or gas fuel stoves are permitted in the backcountry."
        }
      }.freeze

      def initialize(parser_client: BFP::LLM::ParserClient.build, validator: ObservationValidator.new, localized_rule_validator: LocalizedRuleValidator.new, auto_review_policy: AutoReviewPolicy.new)
        @parser_client = parser_client
        @validator = validator
        @localized_rule_validator = localized_rule_validator
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
        return Extractors::NpsAlertsExtractor.new if source.source_type == "nps_alerts_api"
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

        observation = RestrictionObservation.create(
          land_unit_id: land_unit.id,
          restriction_source_id: source.id,
          source_fetch_id: fetch.id,
          scope: observation_scope(result),
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

        persist_localized_rules(fetch, source, land_unit, observation, result)
        observation
      end

      def persist_localized_rules(fetch, source, land_unit, observation, result)
        Array(result["localized_rules"]).each do |rule|
          next unless rule.is_a?(Hash)

          validation = @localized_rule_validator.validate(
            rule,
            source: source,
            extracted_text: fetch.source_document&.extracted_text.to_s
          )
          reasons = (Array(rule["needs_review_reasons"]) + validation.errors).uniq
          geometry = explicit_geojson(rule["geometry_json"])
          area = find_or_create_restriction_area(source, land_unit, rule, geometry)
          review_status = localized_review_status(source, rule, validation)

          persist_localized_fire_use_rule(
            land_unit_id: land_unit.id,
            restriction_area_id: area&.id,
            restriction_observation_id: observation.id,
            restriction_source_id: source.id,
            source_fetch_id: fetch.id,
            slug: localized_rule_slug(source, rule),
            title: presence(rule["title"]) || presence(rule["affected_area"]) || "Localized fire-use rule",
            origin: "parsed_source",
            status: clean_enum(rule["status"], "unknown"),
            campfire_policy: clean_enum(rule["campfire_policy"], "unknown"),
            charcoal_policy: clean_enum(rule["charcoal_policy"], "unknown"),
            gas_stove_policy: clean_enum(rule["gas_stove_policy"], "unknown"),
            liquid_fuel_stove_policy: clean_enum(rule["liquid_fuel_stove_policy"], "unknown"),
            alcohol_stove_policy: clean_enum(rule["alcohol_stove_policy"], "unknown"),
            solid_fuel_stove_policy: clean_enum(rule["solid_fuel_stove_policy"], "unknown"),
            wood_stove_policy: clean_enum(rule["wood_stove_policy"], "unknown"),
            stove_shutoff_valve_required: rule["stove_shutoff_valve_required"],
            stove_requirements_json: Jsonb.wrap(rule["stove_requirements_json"] || {}),
            duration_type: clean_enum(rule["duration_type"], "unknown"),
            effective_start: parse_date(rule["effective_start"]),
            effective_end: parse_date(rule["effective_end"]),
            season_start_month: integer_or_nil(rule["season_start_month"]),
            season_start_day: integer_or_nil(rule["season_start_day"]),
            season_end_month: integer_or_nil(rule["season_end_month"]),
            season_end_day: integer_or_nil(rule["season_end_day"]),
            incident_name: rule["incident_name"],
            incident_number: rule["incident_number"],
            incident_url: rule["incident_url"],
            affected_area: rule["affected_area"],
            geometry_json: Jsonb.wrap(geometry),
            geometry_source_type: geometry ? clean_enum(rule["geometry_source_type"], "unknown") : nil,
            summary: rule["summary"],
            evidence_quotes: Jsonb.wrap(Array(rule["evidence_quotes"])),
            source_url: fetch.source_document&.canonical_url || fetch.final_url || source.url,
            source_title: fetch.source_document&.title || source.name,
            confidence: rule["confidence"].to_f,
            review_status: review_status,
            published_at: (review_status == "auto_accepted") ? Time.now : nil,
            content_fingerprint: localized_rule_fingerprint(source, rule),
            raw_output: Jsonb.wrap(rule),
            metadata_json: Jsonb.wrap(
              "needs_review_reasons" => reasons,
              "validation_errors" => validation.errors,
              "geometry_provenance" => geometry_provenance(source, fetch, rule, geometry)
            )
          )
        end
      end

      def persist_localized_fire_use_rule(attributes)
        existing = LocalizedFireUseRule.first(
          land_unit_id: attributes.fetch(:land_unit_id),
          slug: attributes.fetch(:slug)
        )
        return LocalizedFireUseRule.create(attributes) unless existing

        existing.set(attributes.merge(updated_at: Time.now))
        existing.save
        existing
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

      def integer_or_nil(value)
        return if value.nil? || value.to_s.strip.empty?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def presence(value)
        string = value.to_s.strip
        string.empty? ? nil : string
      end

      def observation_scope(result)
        localized_rules = Array(result["localized_rules"]).select { |rule| rule.is_a?(Hash) }
        return "forestwide" if localized_rules.empty?

        forestwide_fields = %w[fire_danger_rating ifpl_level order_number].any? { |field| presence(result[field]) }
        forestwide_fields ||= presence(result["affected_area"]) && !localized_only_status?(result)
        forestwide_fields ||= !%w[unknown partial].include?(result["status"].to_s)

        forestwide_fields ? "mixed" : "localized"
      end

      def localized_only_status?(result)
        result["status"].to_s == "partial" && result["campfire_policy"].to_s == "unknown"
      end

      def find_or_create_restriction_area(source, land_unit, rule, geometry)
        name = presence(rule["affected_area"]) || presence(rule["title"])
        return unless name

        slug = restriction_area_slug(rule)
        area = RestrictionArea.first(land_unit_id: land_unit.id, slug: slug)
        return area if area

        RestrictionArea.create(
          land_unit_id: land_unit.id,
          slug: slug,
          name: name,
          area_type: clean_enum(rule["area_type"], "unknown"),
          area_description: rule["affected_area"],
          geometry_json: Jsonb.wrap(geometry),
          geometry_source_type: geometry ? clean_enum(rule["geometry_source_type"], "unknown") : nil,
          geometry_source_url: geometry ? source.url : nil,
          geometry_external_id: geometry ? presence(rule["geometry_external_id"]) : nil,
          geometry_acquired_at: geometry ? Time.now : nil,
          geometry_provenance_json: Jsonb.wrap(geometry_provenance(source, nil, rule, geometry)),
          active: true,
          created_at: Time.now,
          updated_at: Time.now
        )
      end

      def localized_review_status(source, rule, validation)
        return "needs_review" unless source.metadata["localized_auto_publish"] == true
        return "needs_review" unless @localized_rule_validator.strong?(rule, validation)

        "auto_accepted"
      end

      def localized_rule_slug(source, rule)
        base = slugify(presence(rule["title"]) || presence(rule["affected_area"]) || "localized-fire-use-rule")
        "#{base}-#{localized_rule_fingerprint(source, rule)[0, 8]}"
      end

      def restriction_area_slug(rule)
        base = slugify(presence(rule["affected_area"]) || presence(rule["title"]) || "localized-area")
        hash = Digest::SHA256.hexdigest([
          rule["area_type"],
          rule["affected_area"],
          rule["geometry_json"]
        ].compact.join("\n"))[0, 8]
        "#{base}-#{hash}"
      end

      def localized_rule_fingerprint(source, rule)
        Digest::SHA256.hexdigest([
          source.respond_to?(:slug) ? source.slug : source.id,
          rule["title"],
          rule["affected_area"],
          rule["status"],
          rule["campfire_policy"],
          rule["effective_start"],
          rule["effective_end"],
          rule["season_start_month"],
          rule["season_start_day"],
          rule["season_end_month"],
          rule["season_end_day"],
          Array(rule["evidence_quotes"]).join("\n")
        ].compact.join("\n"))
      end

      def slugify(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")[0, 72].sub(/-\z/, "")
      end

      def explicit_geojson(value)
        return unless value.is_a?(Hash)
        return unless %w[Point MultiPoint LineString MultiLineString Polygon MultiPolygon GeometryCollection Feature FeatureCollection].include?(value["type"].to_s)

        value
      end

      def geometry_provenance(source, fetch, rule, geometry)
        return {} unless geometry

        {
          "parser_supplied" => true,
          "geometry_source_type" => rule["geometry_source_type"],
          "source_url" => fetch&.source_document&.canonical_url || fetch&.final_url || source.url,
          "source_title" => fetch&.source_document&.title || source.name
        }
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
        result = apply_current_pur_override(result, text, source)
        apply_nps_backcountry_fire_override(result, text, source)
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

      def apply_nps_backcountry_fire_override(result, text, source)
        return result unless source.respond_to?(:authority)
        return result unless source.respond_to?(:source_type)
        return result unless source.respond_to?(:slug)
        return result unless source.authority == "official_nps"
        return result unless source.source_type == "nps_fire_page"

        restriction = NPS_BACKCOUNTRY_FIRE_RESTRICTIONS[source.slug.to_s]
        return result unless restriction
        return result unless text.match?(restriction.fetch(:pattern))

        result.merge(
          "status" => nps_backcountry_status_for(source),
          "campfire_policy" => nps_backcountry_campfire_policy_for(source),
          "fire_danger_rating" => nil,
          "ifpl_level" => nil,
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => restriction.fetch(:affected_area),
          "summary" => restriction.fetch(:summary),
          "evidence_quotes" => [restriction.fetch(:evidence_quote)],
          "confidence" => [result["confidence"].to_f, 0.95].max,
          "needs_review_reasons" => Array(result["needs_review_reasons"]).reject { |reason| ignorable_nps_backcountry_reason?(reason) }
        )
      end

      def ignorable_nps_backcountry_reason?(reason)
        reason.to_s.match?(/LLM parsing is disabled or unavailable|campfire policy|effective dates|permanent|backcountry/i)
      end

      def nps_backcountry_status_for(source)
        PARTIAL_NPS_FIRE_RULE_SOURCES.include?(source.slug.to_s) ? "partial" : "year_round"
      end

      def nps_backcountry_campfire_policy_for(source)
        DEVELOPED_SITE_ONLY_NPS_FIRE_RULE_SOURCES.include?(source.slug.to_s) ? "developed_sites_only" : "prohibited"
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
