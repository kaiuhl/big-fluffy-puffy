require "stringio"
require_relative "../../spec_helper"
require_relative "../../../lib/bfp/llm/parser_client"
require_relative "../../../lib/bfp/llm/bedrock_parser_client"

RSpec.describe BFP::LLM::BedrockParserClient do
  let(:client_class) do
    Struct.new(:payload) do
      def invoke_model(*)
        Struct.new(:body).new(StringIO.new(JSON.generate(payload)))
      end
    end
  end
  let(:source_class) { Struct.new(:source_type, :url) }
  let(:land_unit_class) { Struct.new(:name) }

  it "includes Bedrock token usage and estimated model cost in parser output" do
    payload = {
      "content" => [
        {
          "type" => "tool_use",
          "name" => "record_fire_restriction_observation",
          "input" => {
            "status" => "none",
            "campfire_policy" => "allowed",
            "fire_danger_rating" => nil,
            "ifpl_level" => nil,
            "effective_start" => nil,
            "effective_end" => nil,
            "order_number" => nil,
            "affected_area" => nil,
            "summary" => "No restrictions.",
            "evidence_quotes" => ["No fire restrictions are in effect."],
            "confidence" => 0.9,
            "needs_review_reasons" => []
          }
        }
      ],
      "usage" => {
        "input_tokens" => 1000,
        "output_tokens" => 100,
        "cache_creation_input_tokens" => 0,
        "cache_read_input_tokens" => 0
      }
    }

    result = described_class.new(client: client_class.new(payload)).parse(
      text: "No fire restrictions are in effect.",
      source: source_class.new("fs_fire_info_page", "https://example.test"),
      land_unit: land_unit_class.new("Example National Forest"),
      model_id: "global.anthropic.claude-haiku-4-5-20251001-v1:0"
    )

    expect(result["llm_usage"]).to include("input_tokens" => 1000, "output_tokens" => 100)
    expect(result["llm_cost_estimate_usd"]).to eq(0.0015)
  end
end
