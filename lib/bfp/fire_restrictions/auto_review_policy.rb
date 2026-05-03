module BFP
  module FireRestrictions
    class AutoReviewPolicy
      OFFICIAL_AUTO_SOURCE_TYPES = %w[
        arcgis_feature_layer
        fs_alert_detail
        fs_fire_info_page
        fs_fire_page
      ].freeze
      ACTIVE_AUTO_STATUSES = %w[closure full stage_1 stage_2 year_round].freeze
      HARD_REVIEW_REASON_PATTERNS = [
        /LLM parsing (failed|is disabled)/i,
        /evidence quote does not match/i,
        /lacks .* evidence/i,
        /incident context/i,
        /scan|empty pdf/i,
        /conflict/i,
        /multiple overlapping|overlapping orders/i,
        /geographically limited|not forest[- ]wide|partial area|limited to/i
      ].freeze

      def review_status_for_result(source:, result:, validation:, reasons:)
        return "auto_accepted" if auto_publish_metadata?(source, validation_errors: validation.errors, reasons: reasons, confidence: result["confidence"])

        if official_auto_publish?(
          source: source,
          status: result["status"],
          confidence: result["confidence"],
          validation_errors: validation.errors,
          reasons: reasons
        )
          return "auto_accepted"
        end

        "needs_review"
      end

      def review_status_for_observation(observation)
        source = observation.restriction_source
        reasons = json_array(observation.needs_review_reasons)
        validation_errors = json_array(observation.validation_errors)

        return "auto_accepted" if auto_publish_metadata?(
          source,
          validation_errors: validation_errors,
          reasons: reasons,
          confidence: observation.confidence
        )

        if official_auto_publish?(
          source: source,
          status: observation.status,
          confidence: observation.confidence,
          validation_errors: validation_errors,
          reasons: reasons
        )
          return "auto_accepted"
        end

        observation.review_status
      end

      private

      def auto_publish_metadata?(source, validation_errors:, reasons:, confidence:)
        source.metadata["auto_publish"] == true &&
          confidence.to_f >= 0.8 &&
          validation_errors.empty? &&
          hard_review_reasons(reasons).empty?
      end

      def official_auto_publish?(source:, status:, confidence:, validation_errors:, reasons:)
        return false unless source.authority == "official_usfs"
        return false unless OFFICIAL_AUTO_SOURCE_TYPES.include?(source.source_type)
        return false unless validation_errors.empty?
        return false unless hard_review_reasons(reasons).empty?

        if status.to_s == "none"
          return confidence.to_f >= 0.85
        end

        ACTIVE_AUTO_STATUSES.include?(status.to_s) && confidence.to_f >= 0.9
      end

      def hard_review_reasons(reasons)
        json_array(reasons).select do |reason|
          HARD_REVIEW_REASON_PATTERNS.any? { |pattern| reason.to_s.match?(pattern) }
        end
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
