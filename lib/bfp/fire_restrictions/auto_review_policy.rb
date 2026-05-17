require_relative "observation_validator"

module BFP
  module FireRestrictions
    class AutoReviewPolicy
      OFFICIAL_AUTO_SOURCE_TYPES = %w[
        arcgis_feature_layer
        fs_alerts_page
        fs_alert_detail
        fs_fire_info_page
        fs_fire_page
        nps_alerts_api
        nps_conditions_page
        nps_fire_page
      ].freeze
      OFFICIAL_AUTHORITIES = %w[official_usfs official_nps].freeze
      ACTIVE_AUTO_STATUSES = %w[advisory closure full stage_1 stage_2 year_round].freeze
      HARD_REVIEW_REASON_PATTERNS = [
        /LLM parsing (failed|is disabled)/i,
        /evidence quote does not match/i,
        /lacks .* evidence/i,
        /incident context/i,
        /scan|empty pdf/i,
        /conflict/i,
        /effective end is in the past|expired/i,
        /multiple overlapping|overlapping orders/i,
        /geographically limited|not forest[- ]wide|partial area|limited to/i
      ].freeze

      def review_status_for_result(source:, result:, validation:, reasons:, extracted_text: nil)
        context = result_context(result, validation_errors: validation.errors, reasons: reasons, extracted_text: extracted_text)
        return "auto_accepted" if auto_publish_metadata?(source, context: context)

        if official_auto_publish?(
          source: source,
          context: context
        )
          return "auto_accepted"
        end

        "needs_review"
      end

      def review_status_for_observation(observation)
        source = observation.restriction_source
        context = observation_context(observation)

        return "auto_accepted" if auto_publish_metadata?(source, context: context)

        if official_auto_publish?(
          source: source,
          context: context
        )
          return "auto_accepted"
        end

        observation.review_status
      end

      private

      def auto_publish_metadata?(source, context:)
        source.metadata["auto_publish"] == true &&
          context.fetch(:confidence).to_f >= 0.8 &&
          context.fetch(:hard_review_reasons).empty?
      end

      def official_auto_publish?(source:, context:)
        return false unless OFFICIAL_AUTHORITIES.include?(source.authority)
        return false unless OFFICIAL_AUTO_SOURCE_TYPES.include?(source.source_type)
        return false unless context.fetch(:hard_review_reasons).empty?

        if context.fetch(:status).to_s == "none"
          return false if source.source_type == "fs_alerts_page" && !alerts_page_none_publishable?(context)

          return context.fetch(:confidence).to_f >= 0.85 && none_evidence_clear?(context)
        end

        ACTIVE_AUTO_STATUSES.include?(context.fetch(:status).to_s) &&
          context.fetch(:confidence).to_f >= 0.9
      end

      def result_context(result, validation_errors:, reasons:, extracted_text:)
        context = {
          status: result["status"],
          confidence: result["confidence"],
          evidence_quotes: json_array(result["evidence_quotes"]),
          extracted_text: extracted_text.to_s,
          reasons: json_array(reasons) + json_array(validation_errors)
        }
        context.merge(hard_review_reasons: hard_review_reasons(context))
      end

      def observation_context(observation)
        document = observation.source_fetch&.source_document
        context = {
          status: observation.status,
          confidence: observation.confidence,
          evidence_quotes: json_array(observation.evidence_quotes),
          extracted_text: document&.extracted_text.to_s,
          reasons: json_array(observation.needs_review_reasons) + json_array(observation.validation_errors)
        }
        context.merge(hard_review_reasons: hard_review_reasons(context))
      end

      def hard_review_reasons(context)
        json_array(context.fetch(:reasons)).select do |reason|
          next false if ignorable_none_evidence_issue?(reason, context)

          HARD_REVIEW_REASON_PATTERNS.any? { |pattern| reason.to_s.match?(pattern) }
        end
      end

      def ignorable_none_evidence_issue?(reason, context)
        return false unless context.fetch(:status).to_s == "none"
        return false unless reason.to_s.match?(/evidence quote does not match|None status lacks explicit/i)

        none_evidence_clear?(context)
      end

      def none_evidence_clear?(context)
        evidence_text = [
          json_array(context.fetch(:evidence_quotes)).join("\n"),
          context.fetch(:extracted_text).to_s
        ].join("\n")
        evidence_text.match?(ObservationValidator::NONE_EVIDENCE)
      end

      def alerts_page_none_publishable?(context)
        text = context.fetch(:extracted_text).to_s
        return false unless text.match?(/No active forest fire restriction alerts were listed/i)
        return false if text.match?(/IFPLs and Restrictions|Current Fire Restrictions & Updates|Current IFPL & Restrictions|Fire Restrictions and Danger Levels|South[- ]Central Oregon Fire Management Partnership/i)

        true
      end

      def json_array(value)
        return [] if value.nil?
        return value if value.is_a?(Array)
        return value.to_a if value.respond_to?(:to_a)

        [value]
      end
    end
  end
end
