module BFP
  module LLM
    class FakeParserClient < ParserClient
      def parse(text:, source:, land_unit:, model_id: nil)
        evidence = first_matching_sentence(text)
        lower = text.to_s.downcase

        if lower.match?(/no public[- ]use restrictions|no fire restrictions|restrictions? (have been )?(lifted|rescinded|ended)|campfires? are allowed/)
          result("none", "allowed", evidence, 0.93, model_id)
        elsif lower.match?(/stage\s*2|stage ii/)
          result("stage_2", "prohibited", evidence, 0.9, model_id)
        elsif lower.match?(/stage\s*1|stage i/)
          result("stage_1", "developed_sites_only", evidence, 0.82, model_id)
        elsif lower.match?(/campfires?.{0,80}(prohibited|not allowed|banned)|prohibit.{0,80}campfires?/)
          result("full", "prohibited", evidence, 0.78, model_id)
        else
          result("unknown", "unknown", evidence, 0.35, model_id, ["No explicit restriction status found."])
        end
      end

      private

      def first_matching_sentence(text)
        normalized = text.to_s.gsub(/\s+/, " ").strip
        sentence = normalized.split(/(?<=[.!?])\s+/).find do |candidate|
          candidate.match?(/fire|restriction|campfire|stage|prohibit|allowed|rescinded|lifted/i)
        end

        sentence ? [sentence[0, 500]] : []
      end

      def result(status, campfire_policy, evidence, confidence, model_id, reasons = [])
        {
          "status" => status,
          "campfire_policy" => campfire_policy,
          "fire_danger_rating" => nil,
          "ifpl_level" => nil,
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => nil,
          "summary" => summary_for(status, campfire_policy),
          "evidence_quotes" => evidence,
          "confidence" => confidence,
          "needs_review_reasons" => reasons,
          "localized_rules" => [],
          "parser_provider" => "fake",
          "parser_model_id" => model_id || "fake"
        }
      end

      def summary_for(status, campfire_policy)
        return "No public-use fire restrictions were detected." if status == "none"
        return "Campfires appear to be prohibited." if campfire_policy == "prohibited"
        return "Stage 1 style restrictions were detected." if status == "stage_1"

        "No confident fire restriction status was detected."
      end
    end
  end
end
