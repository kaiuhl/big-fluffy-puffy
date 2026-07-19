require_relative "../../../config/boot"
require_relative "../../spec_helper"
require "bfp/wildfires/proximity"
require "bfp/places/geometry"

ProximityIncidentDouble = Struct.new(
  :name, :acres, :longitude, :latitude, :perimeter_geometry,
  :min_lon, :min_lat, :max_lon, :max_lat,
  keyword_init: true
)

RSpec.describe BFP::Wildfires::Proximity do
  let(:query) { {longitude: -121.0, latitude: 44.0} }

  let(:inside_fire) do
    ProximityIncidentDouble.new(
      name: "Inside", acres: 5000.0, longitude: -121.0, latitude: 44.0,
      perimeter_geometry: {
        "type" => "Polygon",
        "coordinates" => [[[-121.05, 43.95], [-120.95, 43.95], [-120.95, 44.05], [-121.05, 44.05], [-121.05, 43.95]]]
      },
      min_lon: -121.05, min_lat: 43.95, max_lon: -120.95, max_lat: 44.05
    )
  end

  let(:near_fire) { point_fire(name: "Near", miles_north: 5, acres: 45.0) }
  let(:regional_big) { point_fire(name: "RegionalBig", miles_north: 20, acres: 500.0) }
  let(:regional_small) { point_fire(name: "RegionalSmall", miles_north: 20, acres: 10.0, lon: -121.15) }
  let(:far_fire) { point_fire(name: "Far", miles_north: 50, acres: 1000.0) }

  let(:all_fires) { [inside_fire, near_fire, regional_big, regional_small, far_fire] }

  describe ".classify" do
    subject(:results) { described_class.classify(**query, incidents: all_fires) }

    it "assigns tiers by footprint and distance thresholds" do
      by_name = results.to_h { |result| [result[:incident].name, result[:tier]] }

      expect(by_name["Inside"]).to eq(:inside)
      expect(by_name["Near"]).to eq(:near)
      expect(by_name["RegionalBig"]).to eq(:regional)
    end

    it "filters small regional fires below the acreage floor and far fires" do
      names = results.map { |result| result[:incident].name }

      expect(names).not_to include("RegionalSmall")
      expect(names).not_to include("Far")
    end

    it "sorts nearest first with the query point inside at zero distance" do
      expect(results.first[:incident].name).to eq("Inside")
      expect(results.first[:distance_miles]).to eq(0.0)
      expect(results.map { |result| result[:distance_miles] }).to eq(results.map { |result| result[:distance_miles] }.sort)
    end
  end

  describe ".distances" do
    it "returns every fire within the regional radius regardless of acreage" do
      names = described_class.distances(**query, incidents: all_fires).map { |entry| entry[:incident].name }

      expect(names).to contain_exactly("Inside", "Near", "RegionalBig", "RegionalSmall")
    end
  end

  describe ".for_geometry" do
    let(:boundary) do
      BFP::Places::Geometry.geojson_geometry(
        "type" => "Polygon",
        "coordinates" => [[[-121.1, 43.9], [-120.9, 43.9], [-120.9, 44.1], [-121.1, 44.1], [-121.1, 43.9]]]
      )
    end

    it "marks intersecting fires inside and distant fires by boundary distance" do
      outside = point_fire(name: "Outside", miles_north: 15, acres: 200.0)
      results = described_class.for_geometry(boundary, incidents: [inside_fire, outside])
      by_name = results.to_h { |result| [result[:incident].name, result[:tier]] }

      expect(by_name["Inside"]).to eq(:inside)
      expect(by_name["Outside"]).to eq(:near)
    end

    it "keeps fires near the edge of a wide boundary that are far from its centroid" do
      # ~190 miles wide: the east edge sits ~95 miles from the centroid, so a
      # centroid-based prefilter would wrongly drop a fire 5 miles off that edge.
      wide_boundary = BFP::Places::Geometry.geojson_geometry(
        "type" => "Polygon",
        "coordinates" => [[[-125.0, 43.9], [-120.9, 43.9], [-120.9, 44.1], [-125.0, 44.1], [-125.0, 43.9]]]
      )
      edge_fire = point_fire(name: "EdgeFire", miles_north: 15, acres: 200.0, lon: -120.95)

      results = described_class.for_geometry(wide_boundary, incidents: [edge_fire])

      expect(results.map { |result| result[:incident].name }).to include("EdgeFire")
    end

    it "drops fires beyond within_miles even when they qualify for a regional tier" do
      big_regional = point_fire(name: "BigRegional", miles_north: 20, acres: 5000.0)

      default_names = described_class.for_geometry(boundary, incidents: [big_regional]).map { |r| r[:incident].name }
      limited_names = described_class.for_geometry(boundary, incidents: [big_regional], within_miles: described_class::LAND_UNIT_NEARBY_MILES).map { |r| r[:incident].name }

      expect(default_names).to include("BigRegional")
      expect(limited_names).to be_empty
    end

    it "handles GeometryCollection boundaries like the national park shapes" do
      collection = BFP::Places::Geometry.factory.collection([boundary])
      outside = point_fire(name: "Outside", miles_north: 15, acres: 200.0)

      results = described_class.for_geometry(collection, incidents: [inside_fire, outside])
      by_name = results.to_h { |result| [result[:incident].name, result[:tier]] }

      expect(by_name["Inside"]).to eq(:inside)
      expect(by_name["Outside"]).to eq(:near)
    end
  end

  def deg_per_mile
    1609.344 / 6_378_137.0 * 180 / Math::PI
  end

  def point_fire(name:, miles_north:, acres:, lon: -121.0)
    latitude = 44.0 + (miles_north * deg_per_mile)
    ProximityIncidentDouble.new(
      name: name, acres: acres, longitude: lon, latitude: latitude, perimeter_geometry: nil,
      min_lon: lon - 0.03, min_lat: latitude - 0.03, max_lon: lon + 0.03, max_lat: latitude + 0.03
    )
  end
end
