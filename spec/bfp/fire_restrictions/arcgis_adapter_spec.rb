require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/arcgis_adapter"

RSpec.describe BFP::FireRestrictions::ArcgisAdapter do
  let(:source_class) { Struct.new(:url, :metadata) }
  let(:land_unit_class) { Struct.new(:name) }
  let(:source) do
    source_class.new(
      "https://services.example.test/FeatureServer/2",
      {"data_source" => "USFS - Deschutes National Forest"}
    )
  end
  let(:land_unit) { land_unit_class.new("Deschutes National Forest") }

  it "builds the ArcGIS query URL" do
    url = described_class.query_url(source.url)

    expect(url).to include("/query?")
    expect(url).to include("where=1%3D1")
    expect(url).to include("returnGeometry=true")
  end

  it "maps known Central Oregon status values" do
    expect(parse_status(0)).to include("status" => "none", "campfire_policy" => "allowed")
    expect(parse_status(1)).to include("status" => "partial", "campfire_policy" => "developed_sites_only")
    expect(parse_status(2)).to include("status" => "full", "campfire_policy" => "prohibited")
  end

  it "marks unexpected status values unknown" do
    result = parse_status(99)

    expect(result["status"]).to eq("unknown")
    expect(result["needs_review_reasons"].first).to include("Unexpected ArcGIS restriction status")
  end

  def parse_status(status)
    payload = {
      features: [
        {
          attributes: {
            DataSource: "USFS - Deschutes National Forest",
            Status: status,
            Comments: "Central Oregon status"
          },
          geometry: {rings: []}
        }
      ]
    }

    described_class.new.parse(text: JSON.generate(payload), source: source, land_unit: land_unit)
  end
end
