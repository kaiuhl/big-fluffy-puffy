#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "rgeo"
require "time"
require "uri"

ROOT = File.expand_path("../..", __dir__)
OUTPUT_DIR = File.join(ROOT, "data/fire_restrictions/localized_geometries")
BOUNDARY_PATH = File.join(ROOT, "data/fire_restriction_boundaries.geojson")
WILDERNESS_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0/query"
WILDERNESS_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0"
EARTH_RADIUS_METERS = 6_378_137.0
BUFFER_RESOLUTION = 4

TARGETS = [
  {
    slug: "shasta-trinity-mt-shasta-wilderness",
    title: "Mt. Shasta Wilderness",
    land_unit_slug: "shasta-trinity",
    wilderness_name: "Mt. Shasta Wilderness",
    official_rule_source_url: "https://www.fs.usda.gov/r05/shasta-trinity/alerts/mt-shasta-wilderness-area-restrictions"
  }
].freeze

def geos_factory
  raise "RGeo GEOS support is required. Install GEOS before running this script." unless RGeo::Geos.supported?

  RGeo::Geos.factory(buffer_resolution: BUFFER_RESOLUTION)
end

def http_get_json(uri)
  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 10,
    read_timeout: 60,
    use_ssl: uri.scheme == "https"
  ) { |http| http.get(uri.request_uri) }

  raise "Request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def query_wilderness(name)
  uri = URI(WILDERNESS_QUERY_URL)
  uri.query = URI.encode_www_form(
    where: "wildernessname = '#{name.gsub("'", "''")}'",
    outFields: "wildernessname,areaid,wid,gis_acres,boundarystatus",
    returnGeometry: "true",
    outSR: 4326,
    geometryPrecision: 5,
    f: "geojson"
  )

  feature = http_get_json(uri).fetch("features", []).first
  raise "Missing USFS wilderness geometry for #{name}" unless feature

  feature
end

def load_forest_feature(slug)
  feature = JSON.parse(File.read(BOUNDARY_PATH))
    .fetch("features")
    .find { |candidate| candidate.dig("properties", "slug").to_s == slug.to_s }
  raise "Missing forest boundary for #{slug}" unless feature

  feature
end

def coordinate_pairs(value, pairs = [])
  if value.is_a?(Array) && value.length >= 2 && value[0].is_a?(Numeric) && value[1].is_a?(Numeric)
    pairs << [value[0].to_f, value[1].to_f]
  elsif value.is_a?(Array)
    value.each { |item| coordinate_pairs(item, pairs) }
  end

  pairs
end

def bounds_for_features(features)
  pairs = features.flat_map { |feature| coordinate_pairs(feature.fetch("geometry").fetch("coordinates")) }
  raise "Cannot calculate bounds for empty geometry set." if pairs.empty?

  [
    pairs.map(&:first).min,
    pairs.map(&:last).min,
    pairs.map(&:first).max,
    pairs.map(&:last).max
  ]
end

def bounds_center(bounds)
  [
    (bounds[0] + bounds[2]) / 2.0,
    (bounds[1] + bounds[3]) / 2.0
  ]
end

def project_coordinate(lon, lat, origin)
  origin_lon, origin_lat = origin
  origin_lat_radians = origin_lat * Math::PI / 180.0

  [
    (lon - origin_lon) * Math::PI / 180.0 * EARTH_RADIUS_METERS * Math.cos(origin_lat_radians),
    (lat - origin_lat) * Math::PI / 180.0 * EARTH_RADIUS_METERS
  ]
end

def unproject_coordinate(x, y, origin)
  origin_lon, origin_lat = origin
  origin_lat_radians = origin_lat * Math::PI / 180.0

  [
    (origin_lon + (x / (EARTH_RADIUS_METERS * Math.cos(origin_lat_radians)) * 180.0 / Math::PI)).round(5),
    (origin_lat + (y / EARTH_RADIUS_METERS * 180.0 / Math::PI)).round(5)
  ]
end

def ring_points(factory, coordinates, origin)
  pairs = coordinates.map { |coordinate| [coordinate[0].to_f, coordinate[1].to_f] }
  pairs << pairs.first unless pairs.first == pairs.last

  pairs.map do |lon, lat|
    x, y = project_coordinate(lon, lat, origin)
    factory.point(x, y)
  end
end

def polygon_from_coordinates(factory, coordinates, origin)
  exterior = factory.linear_ring(ring_points(factory, coordinates.fetch(0), origin))
  interiors = coordinates.drop(1).map { |ring| factory.linear_ring(ring_points(factory, ring, origin)) }

  factory.polygon(exterior, interiors)
end

def geometry_from_geojson(factory, geometry, origin)
  case geometry.fetch("type")
  when "Polygon"
    polygon_from_coordinates(factory, geometry.fetch("coordinates"), origin)
  when "MultiPolygon"
    factory.multi_polygon(
      geometry.fetch("coordinates").map { |coordinates| polygon_from_coordinates(factory, coordinates, origin) }
    )
  else
    raise "Unsupported GeoJSON geometry type: #{geometry.fetch("type")}"
  end
end

def clean_geometry(geometry)
  return geometry if geometry.valid?

  geometry.make_valid
rescue RGeo::Error::InvalidGeometry
  geometry.make_valid
end

def polygon_coordinates(polygon, origin)
  rings = [polygon.exterior_ring] + polygon.interior_rings
  rings.map do |ring|
    points = ring.points.map { |point| unproject_coordinate(point.x, point.y, origin) }
    points << points.first unless points.first == points.last
    points
  end
end

def multipolygon_coordinates(geometry, origin)
  return [] if geometry.empty?

  case geometry.geometry_type.type_name
  when "Polygon"
    [polygon_coordinates(geometry, origin)]
  when "MultiPolygon"
    geometry.flat_map { |polygon| multipolygon_coordinates(polygon, origin) }
  when "GeometryCollection"
    geometry.flat_map { |part| multipolygon_coordinates(part, origin) }
  else
    []
  end
end

def generated_feature(target)
  factory = geos_factory
  forest_feature = load_forest_feature(target.fetch(:land_unit_slug))
  wilderness_feature = query_wilderness(target.fetch(:wilderness_name))
  origin = bounds_center(bounds_for_features([forest_feature, wilderness_feature]))
  forest_geometry = clean_geometry(geometry_from_geojson(factory, forest_feature.fetch("geometry"), origin))
  wilderness_geometry = clean_geometry(geometry_from_geojson(factory, wilderness_feature.fetch("geometry"), origin))
  clipped_geometry = clean_geometry(forest_geometry.intersection(wilderness_geometry))
  coordinates = multipolygon_coordinates(clipped_geometry, origin)

  raise "No forest/wilderness overlap for #{target.fetch(:slug)}" if coordinates.empty?

  {
    "type" => "Feature",
    "properties" => {
      "slug" => target.fetch(:slug),
      "title" => target.fetch(:title),
      "land_unit_slug" => target.fetch(:land_unit_slug),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "usfs_edw_wilderness",
      "geometry_accuracy" => "source",
      "source_url" => WILDERNESS_LAYER_URL,
      "official_rule_source_url" => target.fetch(:official_rule_source_url),
      "wilderness_name" => wilderness_feature.dig("properties", "wildernessname"),
      "wilderness_areaid" => wilderness_feature.dig("properties", "areaid"),
      "wilderness_wid" => wilderness_feature.dig("properties", "wid"),
      "wilderness_boundary_status" => wilderness_feature.dig("properties", "boundarystatus"),
      "notes" => "Clipped from the official USFS EDW wilderness polygon and BFP forest boundary."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => coordinates
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

TARGETS.each do |target|
  feature = generated_feature(target)
  path = File.join(OUTPUT_DIR, "#{target.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path}."
end
