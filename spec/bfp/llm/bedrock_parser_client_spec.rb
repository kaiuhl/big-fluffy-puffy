require "stringio"
require_relative "../../spec_helper"
require_relative "../../../lib/bfp/llm/parser_client"
require_relative "../../../lib/bfp/llm/bedrock_parser_client"

RSpec.describe BFP::LLM::BedrockParserClient do
  let(:client_class) do
    Class.new do
      attr_reader :requests

      def initialize(payload)
        @payload = payload
        @requests = []
      end

      def invoke_model(**request)
        @requests << request
        Struct.new(:body).new(StringIO.new(JSON.generate(@payload)))
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

  it "sends localized rule schema without changing required forest-wide fields" do
    client = client_class.new(successful_payload)

    parse_with(client)

    schema = request_body_for(client).fetch("tools").first.fetch("input_schema")
    expect(schema.fetch("required")).to eq(%w[
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
    ])

    localized_rules = schema.fetch("properties").fetch("localized_rules")
    rule = localized_rules.fetch("items")
    rule_properties = rule.fetch("properties")

    expect(localized_rules).to include("type" => "array", "maxItems" => 20)
    expect(rule.fetch("additionalProperties")).to be(false)
    expect(rule.fetch("required")).to eq(%w[
      title
      status
      campfire_policy
      charcoal_policy
      gas_stove_policy
      liquid_fuel_stove_policy
      alcohol_stove_policy
      solid_fuel_stove_policy
      wood_stove_policy
      stove_shutoff_valve_required
      duration_type
      effective_start
      effective_end
      season_start_month
      season_start_day
      season_end_month
      season_end_day
      incident_name
      incident_number
      incident_url
      affected_area
      area_type
      geometry_source_type
      summary
      evidence_quotes
      confidence
      needs_review_reasons
    ])
    expect(rule_properties.fetch("campfire_policy").fetch("enum")).to include("fire_pan_required")
    expect(rule_properties.fetch("charcoal_policy").fetch("enum")).to include("prohibited")
    expect(rule_properties.fetch("gas_stove_policy").fetch("enum")).to include("allowed_with_shutoff_valve", "fire_pan_required")
    expect(rule_properties.fetch("alcohol_stove_policy").fetch("enum")).to include("prohibited")
    expect(rule_properties.fetch("duration_type").fetch("enum")).to eq(%w[unknown permanent seasonal temporary incident])
    expect(rule_properties.fetch("area_type").fetch("enum")).to include("wilderness", "corridor", "incident_area")
    expect(rule_properties.fetch("geometry_source_type").fetch("enum")).to include("text_description", "source_map", "source_arcgis_feature", "affected_area_envelope", "derived_nhd_flowline_buffer", "blm_plss_section")
  end

  it "scopes the system prompt to active camping and backpacking fire-use rules" do
    client = client_class.new(successful_payload)

    parse_with(client)

    system_prompt = request_body_for(client).fetch("system")
    expect(system_prompt).to include("camping/backpacking fire-use")
    expect(system_prompt).to include("gas, liquid-fuel, alcohol, solid fuel/tablet, and wood/biomass stoves")
    expect(system_prompt).to include("fire_pan_required")
    expect(system_prompt).to include("shutoff valve")
    expect(system_prompt).to include("Exclude chainsaws, welding, industrial IFPL, generators, off-road travel")
    expect(system_prompt).to include("Only include localized_rules entries for active localized camping/backpacking fire-use restrictions")
    expect(system_prompt).to include('duration_type "permanent"')
    expect(system_prompt).to include('"seasonal"')
    expect(system_prompt).to include('"temporary"')
    expect(system_prompt).to include('"incident"')
  end

  def successful_payload(input = {})
    {
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
          }.merge(input)
        }
      ],
      "usage" => {
        "input_tokens" => 1000,
        "output_tokens" => 100,
        "cache_creation_input_tokens" => 0,
        "cache_read_input_tokens" => 0
      }
    }
  end

  def parse_with(client)
    described_class.new(client: client).parse(
      text: "No fire restrictions are in effect.",
      source: source_class.new("fs_fire_info_page", "https://example.test"),
      land_unit: land_unit_class.new("Example National Forest"),
      model_id: "global.anthropic.claude-haiku-4-5-20251001-v1:0"
    )
  end

  def request_body_for(client)
    JSON.parse(client.requests.fetch(0).fetch(:body))
  end
end
