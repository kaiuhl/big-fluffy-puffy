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

  it "accepts Stage 1 restriction evidence" do
    text = "Stage 1 public use restrictions are in effect. Campfires are only allowed in developed campgrounds."
    result = validate(
      {"status" => "stage_1", "campfire_policy" => "developed_sites_only", "evidence_quotes" => [text]},
      text
    )

    expect(result).to be_valid
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

  def validate(result, text)
    described_class.new.validate(result, source: source, extracted_text: text)
  end
end
