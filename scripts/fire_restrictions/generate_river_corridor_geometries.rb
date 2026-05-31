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
NHD_FLOWLINE_QUERY_URL = "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/6/query"
METERS_PER_MILE = 1609.344
EARTH_RADIUS_METERS = 6_378_137.0
BUFFER_RESOLUTION = 8

CORRIDORS = [
  {
    slug: "wallowa-whitman-hells-canyon-snake-river-quarter-mile-corridor",
    title: "Hells Canyon Snake River 1/4-mile fire-restriction corridor",
    source_url: "https://www.fs.usda.gov/r06/wallowa-whitman/newsroom/releases/hells-canyon-national-recreation-area-annual-fire",
    official_order_url: "https://www.fs.usda.gov/r06/wallowa-whitman/alerts/forest-order-hcnra-fire-closure-order",
    radius_miles: 0.25,
    bbox: [-117.1, 45.23, -116.45, 45.97],
    origin: [-116.75, 45.6],
    gnis_name: "Snake River",
    official_river_mile_start: 247.5,
    official_river_mile_end: 176.0,
    affected_area: "Within 1/4 mile of the Snake River between Hells Canyon Dam and the Oregon-Washington border in Hells Canyon National Recreation Area"
  }
].freeze

def http_get_json(uri)
  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 10,
    read_timeout: 60,
    use_ssl: uri.scheme == "https"
  ) { |http| http.get(uri.request_uri) }

  raise "Geometry request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def query_flowlines(group)
  uri = URI(NHD_FLOWLINE_QUERY_URL)
  uri.query = URI.encode_www_form(
    where: "gnis_name = '#{group.fetch(:gnis_name).gsub("'", "''")}'",
    geometry: group.fetch(:bbox).join(","),
    geometryType: "esriGeometryEnvelope",
    inSR: 4326,
    spatialRel: "esriSpatialRelIntersects",
    outFields: "OBJECTID,permanent_identifier,gnis_name,lengthkm,reachcode,ftype,fcode",
    returnGeometry: "true",
    outSR: 4326,
    f: "geojson"
  )

  features = http_get_json(uri).fetch("features", [])
  features.sort_by { |feature| feature.dig("properties", "OBJECTID").to_i }
end

def geos_factory
  raise "RGeo GEOS support is required. Install GEOS before running this script." unless RGeo::Geos.supported?

  RGeo::Geos.factory(buffer_resolution: BUFFER_RESOLUTION)
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
    (origin_lon + (x / (EARTH_RADIUS_METERS * Math.cos(origin_lat_radians)) * 180.0 / Math::PI)).round(6),
    (origin_lat + (y / EARTH_RADIUS_METERS * 180.0 / Math::PI)).round(6)
  ]
end

def line_from_coordinates(factory, coordinates, origin)
  points = coordinates.map do |coordinate|
    x, y = project_coordinate(coordinate.fetch(0).to_f, coordinate.fetch(1).to_f, origin)
    factory.point(x, y)
  end

  return if points.length < 2

  factory.line_string(points)
end

def multiline_from_coordinates(factory, coordinates, origin)
  lines = coordinates.filter_map { |line| line_from_coordinates(factory, line, origin) }
  return if lines.empty?

  factory.multi_line_string(lines)
end

def geometry_from_geojson(factory, geometry, origin)
  case geometry.fetch("type")
  when "LineString"
    line_from_coordinates(factory, geometry.fetch("coordinates"), origin)
  when "MultiLineString"
    multiline_from_coordinates(factory, geometry.fetch("coordinates"), origin)
  else
    raise "Unsupported NHD flowline geometry type: #{geometry.fetch("type")}"
  end
end

def polygon_coordinates(polygon, origin)
  rings = [polygon.exterior_ring] + polygon.interior_rings
  rings.map do |ring|
    ring.points.map { |point| unproject_coordinate(point.x, point.y, origin) }
  end
end

def multipolygon_coordinates(geometry, origin)
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

def buffered_corridor_coordinates(factory, features, group)
  radius_meters = group.fetch(:radius_miles) * METERS_PER_MILE
  buffers = features.filter_map do |feature|
    geometry = geometry_from_geojson(factory, feature.fetch("geometry"), group.fetch(:origin))
    geometry&.buffer(radius_meters)
  end

  raise "No flowline geometries were buffered for #{group.fetch(:slug)}." if buffers.empty?

  union = factory.collection(buffers).unary_union
  multipolygon_coordinates(union, group.fetch(:origin))
end

def radius_label(radius_miles)
  feet = radius_miles * 5280

  if (radius_miles - 0.25).abs < 0.001
    "1/4 mile"
  elsif (feet - feet.round).abs < 0.1 && feet < 1000
    "#{feet.round} feet"
  else
    "#{radius_miles.round(2)} miles"
  end
end

def generated_feature(group)
  factory = geos_factory
  features = query_flowlines(group)
  raise "No NHD flowlines matched #{group.fetch(:slug)}." if features.empty?

  coordinates = buffered_corridor_coordinates(factory, features, group)
  radius = radius_label(group.fetch(:radius_miles))
  official_segment_miles = group.fetch(:official_river_mile_start) - group.fetch(:official_river_mile_end)
  selected_length_km = features.sum { |feature| feature.dig("properties", "lengthkm").to_f }

  {
    "type" => "Feature",
    "properties" => {
      "slug" => group.fetch(:slug),
      "title" => group.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "derived_nhd_flowline_buffer",
      "geometry_accuracy" => "approximate",
      "buffer_radius_miles" => group.fetch(:radius_miles),
      "source_url" => group.fetch(:source_url),
      "official_order_url" => group.fetch(:official_order_url),
      "nhd_layer_url" => "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/6",
      "nhd_query_where" => "gnis_name = '#{group.fetch(:gnis_name)}'",
      "nhd_query_bbox" => group.fetch(:bbox),
      "selected_flowline_count" => features.length,
      "selected_flowline_length_km" => selected_length_km.round(3),
      "official_river_mile_start" => group.fetch(:official_river_mile_start),
      "official_river_mile_end" => group.fetch(:official_river_mile_end),
      "official_segment_length_miles" => official_segment_miles.round(1),
      "map_subfeatures" => [
        {
          "part_name" => "Snake River corridor",
          "source_kind" => "derived_nhd_flowline_buffer",
          "restriction_detail" => "Fire, campfire, and stove fire are prohibited within #{radius} of the Snake River from June 1 through September 30.",
          "geometry_basis" => "#{radius} buffer around NHD large-scale Snake River flowline features for official river miles #{group.fetch(:official_river_mile_start)} to #{group.fetch(:official_river_mile_end)}",
          "buffer_radius_miles" => group.fetch(:radius_miles),
          "geometry_part_indexes" => (0...coordinates.length).to_a
        }
      ],
      "notes" => "Derived from official NHD large-scale flowline features selected by the official Hells Canyon Dam to Oregon-Washington border segment. The buffer is approximate and the Forest Service order remains the legal boundary."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => coordinates
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

requested_slugs = ENV.fetch("LOCALIZED_GEOMETRY_SLUGS", "").split(",").map(&:strip).reject(&:empty?)
corridors = requested_slugs.empty? ? CORRIDORS : CORRIDORS.select { |group| requested_slugs.include?(group.fetch(:slug)) }
missing_slugs = requested_slugs - corridors.map { |group| group.fetch(:slug) }
raise "Unknown localized geometry slug(s): #{missing_slugs.join(", ")}" if missing_slugs.any?

corridors.each do |group|
  feature = generated_feature(group)
  path = File.join(OUTPUT_DIR, "#{group.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.dig("properties", "selected_flowline_count")} flowlines."
end
