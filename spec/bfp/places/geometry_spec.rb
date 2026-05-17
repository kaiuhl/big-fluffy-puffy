require_relative "../../spec_helper"
require "bfp/places/geometry"

RSpec.describe BFP::Places::Geometry do
  let(:polygon) do
    {
      "type" => "Polygon",
      "coordinates" => [
        [
          [-122.0, 45.0],
          [-121.0, 45.0],
          [-121.0, 46.0],
          [-122.0, 46.0],
          [-122.0, 45.0]
        ]
      ]
    }
  end

  it "checks point containment in GeoJSON polygons" do
    geometry = described_class.geojson_geometry(polygon)
    inside = described_class.factory.point(-121.5, 45.5)
    outside = described_class.factory.point(-120.5, 45.5)

    expect(described_class.contains_point?(geometry, inside)).to be(true)
    expect(described_class.contains_point?(geometry, outside)).to be(false)
  end

  it "calculates a center for display from polygon geometry" do
    center = described_class.center_for(polygon)

    expect(center[0]).to be_between(45.4, 45.6)
    expect(center[1]).to be_between(-121.6, -121.4)
  end

  it "calculates GeoJSON bounds and checks bounding-box intersection" do
    bounds = described_class.bounds_for_geojson(polygon)

    expect(bounds).to eq([-122.0, 45.0, -121.0, 46.0])
    expect(described_class.bounds_intersect?(bounds, [-121.5, 45.5, -120.5, 46.5])).to be(true)
    expect(described_class.bounds_intersect?(bounds, [-120.5, 45.5, -120.1, 46.5])).to be(false)
  end

  it "repairs invalid multipolygons enough to preserve valid forest parts" do
    invalid_multipolygon = {
      "type" => "MultiPolygon",
      "coordinates" => [
        polygon.fetch("coordinates"),
        [
          [
            [-120.0, 45.0],
            [-119.0, 46.0],
            [-120.0, 46.0],
            [-119.0, 45.0],
            [-120.0, 45.0]
          ]
        ]
      ]
    }

    geometry = described_class.geojson_geometry(invalid_multipolygon)
    inside_valid_part = described_class.factory.point(-121.5, 45.5)

    expect(geometry).not_to be_nil
    expect(geometry.valid?).to be(true)
    expect(described_class.contains_point?(geometry, inside_valid_part)).to be(true)
  end
end
