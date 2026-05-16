require_relative "../../spec_helper"
require_relative "../../../config/boot"
require_relative "../../../lib/bfp/fire_restrictions"

RSpec.describe BFP::FireRestrictions::LocalizedRuleValidator do
  subject(:validator) { described_class.new(today: Date.new(2026, 5, 16)) }

  let(:source) { Struct.new(:source_type, keyword_init: true).new(source_type: "fs_fire_info_page") }
  let(:text) { "Campfires are prohibited in Jefferson Park from June 1 through October 15." }

  it "accepts a well-supported localized fire-use rule" do
    result = validator.validate(rule, source: source, extracted_text: text)

    expect(result).to be_valid
    expect(result.errors).to be_empty
    expect(validator.strong?(rule, result)).to be(true)
  end

  it "rejects unsupported evidence and non-GeoJSON geometry" do
    result = validator.validate(
      rule.merge(
        "evidence_quotes" => ["Campfires are prohibited in a different area."],
        "geometry_json" => {"type" => "text_description", "description" => "Jefferson Park"}
      ),
      source: source,
      extracted_text: text
    )

    expect(result).not_to be_valid
    expect(result.errors).to include(a_string_matching(/evidence quote does not match/))
    expect(result.errors).to include("Localized rule geometry_json is not explicit GeoJSON geometry.")
  end

  it "keeps expired restrictive localized rules out of strong validation" do
    result = validator.validate(rule.merge("effective_end" => "2025-10-15"), source: source, extracted_text: text)

    expect(result).not_to be_valid
    expect(result.errors).to include("Localized rule effective_end is in the past.")
    expect(validator.strong?(rule, result)).to be(false)
  end

  def rule
    {
      "title" => "Jefferson Park",
      "status" => "stage_1",
      "campfire_policy" => "prohibited",
      "charcoal_policy" => "prohibited",
      "gas_stove_policy" => "allowed_with_shutoff_valve",
      "liquid_fuel_stove_policy" => "allowed_with_shutoff_valve",
      "alcohol_stove_policy" => "prohibited",
      "solid_fuel_stove_policy" => "prohibited",
      "wood_stove_policy" => "prohibited",
      "stove_shutoff_valve_required" => true,
      "duration_type" => "seasonal",
      "effective_start" => nil,
      "effective_end" => nil,
      "season_start_month" => 6,
      "season_start_day" => 1,
      "season_end_month" => 10,
      "season_end_day" => 15,
      "incident_name" => nil,
      "incident_number" => nil,
      "incident_url" => nil,
      "affected_area" => "Jefferson Park",
      "area_type" => "wilderness",
      "geometry_source_type" => "text_description",
      "summary" => "Campfires are prohibited in Jefferson Park.",
      "evidence_quotes" => ["Campfires are prohibited in Jefferson Park"],
      "confidence" => 0.95,
      "needs_review_reasons" => []
    }
  end
end
