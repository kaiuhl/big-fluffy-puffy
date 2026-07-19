require_relative "../../../config/boot"
require_relative "../../spec_helper"
require "bfp/wildfires/feed"

RSpec.describe BFP::Wildfires::Feed do
  let(:points_body) { File.read(fixture_path("points.geojson")) }
  let(:perimeters_body) { File.read(fixture_path("perimeters.geojson")) }

  describe "query URL builders" do
    it "builds a PNW envelope GeoJSON query for the points layer" do
      url = described_class.points_query_url
      query = URI.decode_www_form(URI(url).query).to_h

      expect(url).to start_with("#{described_class::POINTS_LAYER_URL}/query?")
      expect(query["geometry"]).to eq("-125.1,41.5,-116.4,49.1")
      expect(query["geometryType"]).to eq("esriGeometryEnvelope")
      expect(query["inSR"]).to eq("4326")
      expect(query["spatialRel"]).to eq("esriSpatialRelIntersects")
      expect(query["f"]).to eq("geojson")
      expect(query["outFields"]).to eq("IncidentName,PercentContained,IncidentSize,FireDiscoveryDateTime,FireBehaviorGeneral,IrwinID,POOProtectingUnit,IncidentTypeCategory,IncidentShortDescription,TotalIncidentPersonnel")
    end

    it "builds a query for the perimeters layer with perimeter fields" do
      query = URI.decode_www_form(URI(described_class.perimeters_query_url).query).to_h

      expect(query["outFields"]).to eq("poly_IncidentName,attr_PercentContained,poly_GISAcres,attr_FireDiscoveryDateTime,poly_IRWINID")
      expect(query["f"]).to eq("geojson")
    end
  end

  describe ".parse" do
    subject(:incidents) { described_class.parse(points_body, perimeters_body) }

    it "returns one normalized incident per point feature" do
      expect(incidents.map { |incident| incident[:name] }).to contain_exactly("Cedar Creek", "Whisky Ridge", "Old Ridge")
    end

    it "normalizes IRWIN ids by stripping braces and upcasing" do
      expect(incidents.map { |incident| incident[:irwin_id] }).to include(
        "A1B2C3D4-1111-2222-3333-444455556666",
        "B7C8D9E0-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
      )
    end

    it "joins perimeter geometry and prefers perimeter acres by normalized IRWIN" do
      cedar = incidents.find { |incident| incident[:name] == "Cedar Creek" }

      expect(cedar[:perimeter_geometry_json]).to include("type" => "Polygon")
      expect(cedar[:acres]).to eq(12500.75)
      expect(cedar[:percent_contained]).to eq(40.0)
      expect(cedar[:min_lon]).to eq(-121.75)
      expect(cedar[:min_lat]).to eq(43.97)
      expect(cedar[:max_lon]).to eq(-121.65)
      expect(cedar[:max_lat]).to eq(44.03)
    end

    it "converts epoch-millisecond discovery dates to UTC Time" do
      cedar = incidents.find { |incident| incident[:name] == "Cedar Creek" }

      expect(cedar[:discovered_at]).to be_a(Time)
      expect(cedar[:discovered_at]).to eq(Time.at(1662512400).utc)
    end

    it "derives an AABB from a point buffer when no perimeter exists" do
      whisky = incidents.find { |incident| incident[:name] == "Whisky Ridge" }

      expect(whisky[:perimeter_geometry_json]).to be_nil
      expect(whisky[:acres]).to eq(45.0)
      expect(whisky[:min_lon]).to be < -120.50
      expect(whisky[:max_lon]).to be > -120.50
      expect(whisky[:min_lat]).to be < 43.50
      expect(whisky[:max_lat]).to be > 43.50
    end

    it "raises FeedError for malformed payloads" do
      expect {
        described_class.parse(File.read(fixture_path("malformed.geojson")), perimeters_body)
      }.to raise_error(BFP::Wildfires::Feed::FeedError, /invalid JSON/)
    end

    it "raises FeedError for ArcGIS error payloads served with HTTP 200" do
      error_body = {"error" => {"code" => 500, "message" => "Error performing query operation"}}.to_json

      expect {
        described_class.parse(error_body, perimeters_body)
      }.to raise_error(BFP::Wildfires::Feed::FeedError, /ArcGIS error/)
    end

    it "raises FeedError when the features array is missing" do
      expect {
        described_class.parse({"type" => "FeatureCollection"}.to_json, perimeters_body)
      }.to raise_error(BFP::Wildfires::Feed::FeedError, /no features array/)
    end

    it "leaves information_url nil when no InciWeb entries are supplied" do
      expect(incidents.map { |incident| incident[:information_url] }).to all(be_nil)
    end
  end

  describe ".parse_inciweb" do
    let(:inciweb_body) { File.read(fixture_path("inciweb.xml")) }

    it "parses items into normalized unit/name/url entries" do
      entries = described_class.parse_inciweb(inciweb_body)

      expect(entries).to include(
        {unit: "ORDEF", name: "cedar creek", url: "https://inciweb.wildfire.gov/incident-information/ordef-cedar-creek-fire"}
      )
      # Units upcase; names drop a trailing "Fire" and downcase so they line up
      # with WFIGS IncidentName.
      expect(entries.map { |entry| entry[:name] }).to contain_exactly("cedar creek", "whisky ridge", "turner")
      expect(entries.map { |entry| entry[:unit] }).to contain_exactly("ORDEF", "WAOKA", "IDNIA")
    end

    it "raises FeedError on nil, empty, or non-RSS bodies" do
      expect { described_class.parse_inciweb(nil) }.to raise_error(BFP::Wildfires::Feed::FeedError)
      expect { described_class.parse_inciweb("   ") }.to raise_error(BFP::Wildfires::Feed::FeedError)
      expect { described_class.parse_inciweb("not xml at all") }.to raise_error(BFP::Wildfires::Feed::FeedError)
    end

    it "returns an empty list for a well-formed RSS feed with no incidents" do
      empty = %(<?xml version="1.0"?><rss version="2.0"><channel><title>InciWeb</title></channel></rss>)

      expect(described_class.parse_inciweb(empty)).to eq([])
    end
  end

  describe ".parse joining InciWeb information URLs" do
    let(:inciweb_entries) { described_class.parse_inciweb(File.read(fixture_path("inciweb.xml"))) }
    subject(:joined) { described_class.parse(points_body, perimeters_body, inciweb_entries: inciweb_entries) }

    it "attaches an information_url by an exact unit and name match" do
      cedar = joined.find { |incident| incident[:name] == "Cedar Creek" }

      expect(cedar[:information_url]).to eq("https://inciweb.wildfire.gov/incident-information/ordef-cedar-creek-fire")
    end

    it "falls back to a unique name-only match when the protecting unit differs" do
      whisky = joined.find { |incident| incident[:name] == "Whisky Ridge" }

      expect(whisky[:information_url]).to eq("https://inciweb.wildfire.gov/incident-information/waoka-whisky-ridge-fire")
    end

    it "leaves information_url nil when nothing matches" do
      old_ridge = joined.find { |incident| incident[:name] == "Old Ridge" }

      expect(old_ridge[:information_url]).to be_nil
    end

    it "does not name-match when more than one entry shares that name" do
      duplicate = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <item><title>WAOKA Whisky Ridge Fire</title><link>http://inciweb.wildfire.gov/incident-information/waoka-whisky-ridge-fire</link></item>
          <item><title>IDABC Whisky Ridge Fire</title><link>http://inciweb.wildfire.gov/incident-information/idabc-whisky-ridge-fire</link></item>
        </channel></rss>
      XML
      entries = described_class.parse_inciweb(duplicate)

      whisky = described_class.parse(points_body, perimeters_body, inciweb_entries: entries)
        .find { |incident| incident[:name] == "Whisky Ridge" }

      expect(whisky[:information_url]).to be_nil
    end
  end

  def fixture_path(name)
    File.join(BFP.root, "spec/fixtures/wildfires", name)
  end
end
