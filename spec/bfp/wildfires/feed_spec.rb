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
      expect(query["outFields"]).to eq("IncidentName,PercentContained,IncidentSize,FireDiscoveryDateTime,FireBehaviorGeneral,IrwinID")
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
  end

  def fixture_path(name)
    File.join(BFP.root, "spec/fixtures/wildfires", name)
  end
end
