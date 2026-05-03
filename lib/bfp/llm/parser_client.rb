module BFP
  module LLM
    class ParserClient
      SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[
          status
          campfire_policy
          fire_danger_rating
          ifpl_level
          effective_start
          effective_end
          order_number
          affected_area
          summary
          evidence_quotes
          confidence
          needs_review_reasons
        ],
        properties: {
          status: {
            type: "string",
            enum: %w[unknown none advisory partial stage_1 stage_2 full closure year_round]
          },
          campfire_policy: {
            type: "string",
            enum: %w[unknown allowed developed_sites_only prohibited propane_allowed stoves_only]
          },
          fire_danger_rating: {type: ["string", "null"]},
          ifpl_level: {type: ["string", "null"]},
          effective_start: {type: ["string", "null"], description: "ISO 8601 date or null"},
          effective_end: {type: ["string", "null"], description: "ISO 8601 date or null"},
          order_number: {type: ["string", "null"]},
          affected_area: {type: ["string", "null"]},
          summary: {type: ["string", "null"]},
          evidence_quotes: {
            type: "array",
            items: {type: "string"},
            maxItems: 6
          },
          confidence: {type: "number", minimum: 0, maximum: 1},
          needs_review_reasons: {
            type: "array",
            items: {type: "string"},
            maxItems: 8
          }
        }
      }.freeze

      def self.build
        return FakeParserClient.new if ENV.fetch("LLM_PROVIDER", "bedrock") == "fake"
        return FakeParserClient.new if BFP.env == "test"

        BedrockParserClient.new
      end
    end
  end
end
