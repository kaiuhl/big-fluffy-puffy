require_relative "../../spec_helper"
require_relative "../../../config/boot"
require_relative "../../../lib/bfp/fire_restrictions/source_parser"

RSpec.describe BFP::FireRestrictions::SourceParser do
  around do |example|
    previous = ENV["LLM_ESCALATION_ENABLED"]
    ENV.delete("LLM_ESCALATION_ENABLED")
    example.run
  ensure
    if previous.nil?
      ENV.delete("LLM_ESCALATION_ENABLED")
    else
      ENV["LLM_ESCALATION_ENABLED"] = previous
    end
  end

  let(:parser) { described_class.new(parser_client: Object.new, validator: Object.new) }
  let(:source) { Struct.new(:source_type, :id, :authority, keyword_init: true).new(source_type: "fs_fire_info_page", id: 1, authority: "official_usfs") }
  let(:land_unit) { Struct.new(:id, keyword_init: true).new(id: 1) }

  it "keeps escalation disabled by default even when the primary result is uncertain" do
    result = parser_result("unknown", confidence: 0.2)
    validation = validation_result(false)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(false)
  end

  it "allows escalation when explicitly enabled and a trigger is present" do
    ENV["LLM_ESCALATION_ENABLED"] = "true"
    result = parser_result("unknown", confidence: 0.2)
    validation = validation_result(true)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(true)
  end

  it "does not escalate parser failures" do
    ENV["LLM_ESCALATION_ENABLED"] = "true"
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing failed: AccessDenied"])
    validation = validation_result(false)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(false)
  end

  it "passes extracted text into the auto-review policy" do
    policy = Object.new
    parser = described_class.new(parser_client: Object.new, validator: Object.new, auto_review_policy: policy)
    result = parser_result("none", confidence: 0.95)
    validation = validation_result(true, errors: [])
    captured_text = nil

    policy.define_singleton_method(:review_status_for_result) do |extracted_text:, **|
      captured_text = extracted_text
      "auto_accepted"
    end

    status = parser.send(
      :review_status_for,
      source,
      result,
      validation,
      [],
      extracted_text: "No fire restrictions are in effect."
    )

    expect(status).to eq("auto_accepted")
    expect(captured_text).to eq("No fire restrictions are in effect.")
  end

  it "normalizes current Seasonal Restrictions/Phase A public-use rows to an advisory" do
    result = parser_result("unknown", confidence: 0.3, reasons: ["Current PUR phase not explicitly stated as Phase A"])
    text = <<~TEXT
      Industrial Fire Precaution Levels (IFPL) and current public use restrictions at Malheur National Forest.
      Fire Danger: LOW
      IFPL: I
      PUR: Seasonal Restrictions
      Phase A
    TEXT

    normalized = parser.send(:apply_structural_overrides, result, text, source)

    expect(normalized).to include(
      "status" => "advisory",
      "campfire_policy" => "allowed",
      "fire_danger_rating" => "LOW",
      "ifpl_level" => "I"
    )
    expect(normalized["confidence"]).to eq(0.9)
    expect(normalized["evidence_quotes"]).to eq(["Fire Danger: LOW", "IFPL: I", "PUR: Seasonal Restrictions"])
    expect(normalized["needs_review_reasons"]).to be_empty
  end

  it "normalizes Mount Rainier's official backcountry fire rule without LLM parsing" do
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing is disabled or unavailable."])
    source = nps_source("mount-rainier-wilderness-regulations")
    text = <<~TEXT
      The following items or activities are prohibited on the trails and in the backcountry of Mount Rainier National Park:
      Fire (white gas, iso-butane cartridge, alcohol stoves are okay. No bio-fuel stoves; i.e., those that burn twigs, sticks, cones, etc.)
    TEXT

    normalized = parser.send(:apply_structural_overrides, result, text, source)

    expect(normalized).to include(
      "status" => "year_round",
      "campfire_policy" => "prohibited",
      "affected_area" => "trails and backcountry"
    )
    expect(normalized["confidence"]).to eq(0.95)
    expect(normalized["needs_review_reasons"]).to be_empty
  end

  it "normalizes Crater Lake's official backcountry campfire rule without LLM parsing" do
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing is disabled or unavailable."])
    source = nps_source("crater-lake-backcountry-faq")

    normalized = parser.send(
      :apply_structural_overrides,
      result,
      "Campfires are prohibited in the park's backcountry. Backpacking stoves or camp stoves that utilize fuel canisters and/or canisters of liquid fuel are permitted.",
      source
    )

    expect(normalized).to include(
      "status" => "year_round",
      "campfire_policy" => "prohibited",
      "affected_area" => "park backcountry"
    )
    expect(normalized["evidence_quotes"]).to eq(["Campfires are prohibited in the park's backcountry."])
    expect(normalized["needs_review_reasons"]).to be_empty
  end

  it "normalizes North Cascades camp-specific wilderness fire rules without LLM parsing" do
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing is disabled or unavailable."])
    source = nps_source("north-cascades-wilderness-trip-planner")
    text = <<~TEXT
      See the table below for information on group size limitation for each backcountry camp, food storage requirements, and campfire rules.
      Fisher Pit Canister 4,4,4 4 No Campfires, Bear Canister Required
    TEXT

    normalized = parser.send(:apply_structural_overrides, result, text, source)

    expect(normalized).to include(
      "status" => "partial",
      "campfire_policy" => "prohibited",
      "affected_area" => "listed backcountry camps and cross-country zones"
    )
    expect(normalized["needs_review_reasons"]).to be_empty
  end

  it "normalizes Olympic elevation and coast fire rules without LLM parsing" do
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing is disabled or unavailable."])
    source = nps_source("olympic-national-park-wilderness-regulations")
    text = <<~TEXT
      Campfires and wood-burning camp stoves are allowed below 3,500 feet only. This helps protect subalpine forests and soils.
      Campfires and wood-burning camp stoves are not allowed on the coast between the headland at Wedding Rocks and the headland north of Yellow Banks.
    TEXT

    normalized = parser.send(:apply_structural_overrides, result, text, source)

    expect(normalized).to include(
      "status" => "partial",
      "campfire_policy" => "prohibited",
      "affected_area" => "wilderness above 3,500 feet and the coast between Wedding Rocks and Yellow Banks"
    )
    expect(normalized["evidence_quotes"]).to eq(["Campfires and wood-burning camp stoves are allowed below 3,500 feet only."])
  end

  it "normalizes Lassen frontcountry-only fire rules without LLM parsing" do
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing is disabled or unavailable."])
    source = nps_source("lassen-volcanic-fire-regulations")
    text = <<~TEXT
      Fires are only allowed in park-provided grills or fire rings in established frontcountry campgrounds and day use areas.
      Fires are not permitted in any other area of the park, including backcountry and wilderness areas.
    TEXT

    normalized = parser.send(:apply_structural_overrides, result, text, source)

    expect(normalized).to include(
      "status" => "year_round",
      "campfire_policy" => "developed_sites_only",
      "affected_area" => "outside established frontcountry campgrounds and day-use areas"
    )
    expect(normalized["needs_review_reasons"]).to be_empty
  end

  it "marks parser results with only localized rules as localized observations" do
    result = parser_result("partial", confidence: 0.8).merge(
      "campfire_policy" => "unknown",
      "localized_rules" => [localized_rule]
    )

    expect(parser.send(:observation_scope, result)).to eq("localized")
  end

  it "marks parser results with forestwide and localized signals as mixed observations" do
    result = parser_result("stage_1", confidence: 0.9).merge(
      "campfire_policy" => "developed_sites_only",
      "localized_rules" => [localized_rule]
    )

    expect(parser.send(:observation_scope, result)).to eq("mixed")
  end

  it "keeps localized rules in review by default even when validation is strong" do
    validation = BFP::FireRestrictions::LocalizedRuleValidator::Result.new(valid?: true, errors: [])
    source = source_with_metadata({})

    expect(parser.send(:localized_review_status, source, localized_rule.merge("confidence" => 0.95), validation)).to eq("needs_review")
  end

  it "allows localized auto acceptance only with explicit localized metadata and strong validation" do
    validation = BFP::FireRestrictions::LocalizedRuleValidator::Result.new(valid?: true, errors: [])
    source = source_with_metadata("localized_auto_publish" => true)

    expect(parser.send(:localized_review_status, source, localized_rule.merge("confidence" => 0.95), validation)).to eq("auto_accepted")
  end

  it "drops non-GeoJSON parser geometry before localized persistence" do
    expect(parser.send(:explicit_geojson, {"type" => "text_description", "description" => "wilderness boundary"})).to be_nil
    expect(parser.send(:explicit_geojson, {"type" => "Polygon", "coordinates" => []})).to eq({"type" => "Polygon", "coordinates" => []})
  end

  it "persists localized rules with needs_review status and nil geometry unless parser supplied GeoJSON" do
    created_rules = []
    created_areas = []
    stub_const("BFP::FireRestrictions::LocalizedFireUseRule", Class.new do
      define_singleton_method(:first) { |**| nil }
      define_singleton_method(:create) { |attributes| created_rules << attributes }
    end)
    stub_const("BFP::FireRestrictions::RestrictionArea", Class.new do
      define_singleton_method(:first) { |**| nil }
      define_singleton_method(:create) do |attributes|
        created_areas << attributes
        Struct.new(:id).new(99)
      end
    end)

    source = source_with_metadata("localized_auto_publish" => true)
    fetch = Struct.new(:id, :final_url, :source_document, keyword_init: true).new(
      id: 7,
      final_url: "https://example.test/final",
      source_document: Struct.new(:extracted_text, :canonical_url, :title, keyword_init: true).new(
        extracted_text: "Campfires are prohibited in Jefferson Park.",
        canonical_url: "https://example.test/canonical",
        title: "Fire order"
      )
    )
    observation = Struct.new(:id, keyword_init: true).new(id: 42)
    result = {"localized_rules" => [localized_rule.merge("geometry_json" => {"type" => "text_description"})]}

    parser.send(:persist_localized_rules, fetch, source, land_unit, observation, result)

    expect(created_areas.first).to include(geometry_json: nil, geometry_source_type: nil)
    expect(created_rules.first).to include(
      restriction_observation_id: 42,
      restriction_area_id: 99,
      review_status: "needs_review",
      geometry_json: nil
    )
    expect(created_rules.first.fetch(:slug)).to start_with("jefferson-park-")
  end

  def should_escalate?(result, validation, text)
    parser.send(:should_escalate?, result, validation, text, source, land_unit)
  end

  def parser_result(status, confidence:, reasons: [])
    {
      "status" => status,
      "confidence" => confidence,
      "needs_review_reasons" => reasons
    }
  end

  def localized_rule
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
      "evidence_quotes" => ["Campfires are prohibited in Jefferson Park."],
      "confidence" => 0.95,
      "needs_review_reasons" => []
    }
  end

  def source_with_metadata(metadata)
    Struct.new(:source_type, :id, :authority, :slug, :name, :url, :metadata, keyword_init: true).new(
      source_type: "fs_fire_info_page",
      id: 1,
      authority: "official_usfs",
      slug: "willamette-fire-info",
      name: "Willamette Fire Info",
      url: "https://example.test/fire",
      metadata: metadata
    )
  end

  def nps_source(slug)
    Struct.new(:source_type, :id, :authority, :slug, keyword_init: true).new(
      source_type: "nps_fire_page",
      id: 2,
      authority: "official_nps",
      slug: slug
    )
  end

  def validation_result(valid, errors: [])
    Object.new.tap do |object|
      object.define_singleton_method(:valid?) { valid }
      object.define_singleton_method(:errors) { errors }
    end
  end
end
