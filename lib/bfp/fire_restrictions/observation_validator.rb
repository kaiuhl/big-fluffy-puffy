require "date"

module BFP
  module FireRestrictions
    class ObservationValidator
      RESTRICTIVE_STATUSES = %w[advisory partial stage_1 stage_2 full closure year_round].freeze
      RESTRICTIVE_EVIDENCE = /prohibit|restriction|ban|not allowed|closed|closure|stage\s*(1|2|i|ii)|forest order|public[- ]use/i
      NONE_EVIDENCE = /no (?:current |active )?(?:public[- ]use |fire public use |fire |campfire )?restrictions(?: \(?PURS\)?)?(?: are)?(?: currently)?(?: in effect| in place)?|(?:fire ban|fire restrictions?) (?:is|are) not in effect|no active forest fire restriction alerts were listed|restrictions?.{0,80}(lifted|rescinded|ended)|lifted.{0,80}restrictions?|rescinded|campfires? are allowed/i
      INCIDENT_CONTEXT_TYPES = %w[inciweb_feed nifc_feature_layer].freeze

      Result = Struct.new(:valid?, :errors, keyword_init: true)

      def initialize(today: Date.today)
        @today = today
      end

      def validate(result, source:, extracted_text:)
        errors = []
        text = extracted_text.to_s
        evidence_quotes = Array(result["evidence_quotes"]).compact.map(&:to_s)

        unless source.source_type == "arcgis_feature_layer"
          evidence_quotes.each do |quote|
            next if quote.strip.empty?
            next if ignorable_supporting_quote_mismatch?(result, quote, evidence_quotes, text)

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
        evidence_text = status_evidence_text(status, evidence_quotes, text)

        if RESTRICTIVE_STATUSES.include?(status) && !evidence_text.match?(RESTRICTIVE_EVIDENCE)
          errors << "Restrictive status lacks restriction/prohibition evidence."
        end

        validate_effective_end(result, errors) if RESTRICTIVE_STATUSES.include?(status)

        if status == "none" && !evidence_text.match?(NONE_EVIDENCE)
          errors << "None status lacks explicit no-restrictions/lifted/rescinded evidence."
        end
      end

      def validate_effective_end(result, errors)
        effective_end = parse_date(result["effective_end"])
        return unless effective_end
        return unless effective_end < @today

        errors << "Restrictive status effective end is in the past."
      end

      def ignorable_supporting_quote_mismatch?(result, quote, evidence_quotes, text)
        return false if includes_normalized?(text, quote)
        return false if status_evidence_quote?(result["status"].to_s, quote)

        status_evidence_quotes(result["status"].to_s, evidence_quotes).any?
      end

      def status_evidence_text(status, evidence_quotes, text)
        quoted_evidence = status_evidence_quotes(status, evidence_quotes).join("\n")
        return [quoted_evidence, text].join("\n") unless quoted_evidence.empty?

        evidence_quotes.empty? ? text : evidence_quotes.join("\n")
      end

      def status_evidence_quotes(status, evidence_quotes)
        evidence_quotes.select { |quote| status_evidence_quote?(status, quote) }
      end

      def status_evidence_quote?(status, quote)
        case status.to_s
        when "none"
          quote.to_s.match?(NONE_EVIDENCE)
        else
          RESTRICTIVE_STATUSES.include?(status.to_s) && quote.to_s.match?(RESTRICTIVE_EVIDENCE)
        end
      end

      def includes_normalized?(haystack, needle)
        normalize(haystack).include?(normalize(needle))
      end

      def parse_date(value)
        return if value.to_s.strip.empty?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def normalize(value)
        value.to_s.tr("\u00a0\u202f", "  ").gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
