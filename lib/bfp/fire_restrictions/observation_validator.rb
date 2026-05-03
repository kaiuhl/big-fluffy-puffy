module BFP
  module FireRestrictions
    class ObservationValidator
      RESTRICTIVE_STATUSES = %w[advisory partial stage_1 stage_2 full closure year_round].freeze
      RESTRICTIVE_EVIDENCE = /prohibit|restriction|ban|not allowed|closed|closure|stage\s*(1|2|i|ii)|forest order|public[- ]use/i
      NONE_EVIDENCE = /no public[- ]use restrictions|no fire restrictions|restrictions?.{0,40}(lifted|rescinded|ended)|lifted.{0,40}restrictions?|rescinded|campfires? are allowed|no restrictions in effect/i
      INCIDENT_CONTEXT_TYPES = %w[inciweb_feed nifc_feature_layer].freeze

      Result = Struct.new(:valid?, :errors, keyword_init: true)

      def validate(result, source:, extracted_text:)
        errors = []
        text = extracted_text.to_s
        evidence_quotes = Array(result["evidence_quotes"]).compact.map(&:to_s)

        unless source.source_type == "arcgis_feature_layer"
          evidence_quotes.each do |quote|
            next if quote.strip.empty?

            unless includes_normalized?(text, quote)
              errors << "Evidence quote does not match extracted text: #{quote[0, 120]}"
            end
          end
        end

        unless source.source_type == "arcgis_feature_layer"
          validate_status_evidence(result, evidence_quotes, text, errors)
        end

        if INCIDENT_CONTEXT_TYPES.include?(source.source_type) && result["campfire_policy"].to_s != "unknown"
          errors << "Incident context sources cannot set campfire policy."
        end

        Result.new(valid?: errors.empty?, errors: errors)
      end

      private

      def validate_status_evidence(result, evidence_quotes, text, errors)
        status = result["status"].to_s
        evidence_text = evidence_quotes.join("\n")
        evidence_text = text if evidence_text.empty?

        if RESTRICTIVE_STATUSES.include?(status) && !evidence_text.match?(RESTRICTIVE_EVIDENCE)
          errors << "Restrictive status lacks restriction/prohibition evidence."
        end

        if status == "none" && !evidence_text.match?(NONE_EVIDENCE)
          errors << "None status lacks explicit no-restrictions/lifted/rescinded evidence."
        end
      end

      def includes_normalized?(haystack, needle)
        normalize(haystack).include?(normalize(needle))
      end

      def normalize(value)
        value.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
