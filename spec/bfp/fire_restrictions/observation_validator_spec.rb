require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/observation_validator"

RSpec.describe BFP::FireRestrictions::ObservationValidator do
  let(:source_class) { Struct.new(:source_type) }

  let(:source) { source_class.new("fs_fire_info_page") }

  it "rejects evidence that does not match extracted text" do
    result = validate(
      {"status" => "stage_1", "campfire_policy" => "developed_sites_only", "evidence_quotes" => ["not in text"]},
      "Stage 1 public use restrictions are in effect."
    )

    expect(result).not_to be_valid
    expect(result.errors.first).to include("Evidence quote does not match")
  end

  it "does not reject a mismatched supporting quote when core none evidence is present" do
    result = validate(
      {
        "status" => "none",
        "campfire_policy" => "unknown",
        "evidence_quotes" => [
          "There are currently no fire restrictions on the Olympic National Forest.",
          "Fireworks and explosives (including explosive targets) are always prohibited on national forest lands."
        ]
      },
      "There are currently no fire restrictions on the Olympic National Forest. Fireworks and explosives are always prohibited on national forest lands."
    )

    expect(result).to be_valid
  end

  it "accepts Stage 1 restriction evidence" do
    text = "Stage 1 public use restrictions are in effect. Campfires are only allowed in developed campgrounds."
    result = validate(
      {"status" => "stage_1", "campfire_policy" => "developed_sites_only", "evidence_quotes" => [text]},
      text
    )

    expect(result).to be_valid
  end

  it "rejects expired restrictive observations" do
    text = "Stage 2 public use restrictions are in effect. Campfires are prohibited."
    result = described_class.new(today: Date.new(2026, 5, 3)).validate(
      {
        "status" => "stage_2",
        "campfire_policy" => "prohibited",
        "effective_end" => "2025-11-30",
        "evidence_quotes" => [text]
      },
      source: source,
      extracted_text: text
    )

    expect(result).not_to be_valid
    expect(result.errors).to include("Restrictive status effective end is in the past.")
  end

  it "requires explicit evidence for no restrictions" do
    result = validate(
      {"status" => "none", "campfire_policy" => "allowed", "evidence_quotes" => ["Fire danger is low."]},
      "Fire danger is low."
    )

    expect(result).not_to be_valid
    expect(result.errors).to include("None status lacks explicit no-restrictions/lifted/rescinded evidence.")
  end

  it "accepts lifted restrictions evidence" do
    text = "Public use restrictions have been rescinded across the forest."
    result = validate(
      {"status" => "none", "campfire_policy" => "allowed", "evidence_quotes" => [text]},
      text
    )

    expect(result).to be_valid
  end

  it "accepts no current fire restrictions evidence" do
    text = "There are no current fire restrictions."
    result = validate(
      {"status" => "none", "campfire_policy" => "unknown", "evidence_quotes" => [text]},
      text
    )

    expect(result).to be_valid
  end

  it "accepts structured alerts-page evidence for no active forest fire restriction alerts" do
    text = "No active forest fire restriction alerts were listed in the Forest Alerts section."
    result = validate(
      {"status" => "none", "campfire_policy" => "unknown", "evidence_quotes" => [text]},
      text
    )

    expect(result).to be_valid
  end

  it "normalizes non-breaking spaces when matching evidence quotes" do
    result = validate(
      {
        "status" => "unknown",
        "campfire_policy" => "unknown",
        "evidence_quotes" => ["Fireworks and explosives are always prohibited on national forest lands."]
      },
      "Fireworks and explosives are always prohibited\u00a0on national forest lands."
    )

    expect(result.errors).to be_empty
  end

  it "prevents incident context sources from setting campfire policy" do
    inciweb_source = source_class.new("inciweb_feed")
    result = described_class.new.validate(
      {"status" => "unknown", "campfire_policy" => "prohibited", "evidence_quotes" => []},
      source: inciweb_source,
      extracted_text: "Incident information."
    )

    expect(result).not_to be_valid
    expect(result.errors).to include("Incident context sources cannot set campfire policy.")
  end

  it "does not require exact raw-text evidence matching for ArcGIS feature layers" do
    arcgis_source = source_class.new("arcgis_feature_layer")
    result = described_class.new.validate(
      {"status" => "none", "campfire_policy" => "allowed", "evidence_quotes" => ["normalized feature evidence"]},
      source: arcgis_source,
      extracted_text: "{\"features\":[]}"
    )

    expect(result).to be_valid
  end

  def validate(result, text)
    described_class.new.validate(result, source: source, extracted_text: text)
  end
end
