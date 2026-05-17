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
GNIS_BASE_URL = "https://carto-wfs.nationalmap.gov/arcgis/rest/services/geonames/MapServer"
EARTH_RADIUS_METERS = 6_378_137.0
METERS_PER_MILE = 1609.344
BUFFER_RESOLUTION = 12

GROUPS = [
  {
    slug: "mt-hood-ramona-falls-mcneil-point-500-foot-campfire-buffer",
    title: "Mount Hood Wilderness Ramona Falls and McNeil Point 500-foot campfire buffers",
    source_url: "https://www.fs.usda.gov/media/234596",
    radius_miles: 500.0 / 5280.0,
    bbox: [-121.9, 45.3, -121.65, 45.45],
    center: [-121.75, 45.39],
    features: [
      {
        name: "Ramona Falls",
        layer_id: 4,
        feature_class: "Falls",
        state_alpha: "OR"
      },
      {
        name: "McNeil Point",
        layer_id: 2,
        feature_class: "Ridge",
        state_alpha: "OR"
      }
    ]
  }
].freeze

def http_get_json(uri)
  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 10,
    read_timeout: 30,
    use_ssl: uri.scheme == "https"
  ) { |http| http.get(uri.request_uri) }

  raise "GNIS request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def query_gnis(feature, bbox)
  uri = URI("#{GNIS_BASE_URL}/#{feature.fetch(:layer_id)}/query")
  uri.query = URI.encode_www_form(
    where: [
      "gaz_name = '#{feature.fetch(:name).gsub("'", "''")}'",
      "state_alpha = '#{feature.fetch(:state_alpha)}'",
      "gaz_featureclass = '#{feature.fetch(:feature_class).gsub("'", "''")}'"
    ].join(" AND "),
    geometry: bbox.join(","),
    geometryType: "esriGeometryEnvelope",
    inSR: 4326,
    spatialRel: "esriSpatialRelIntersects",
    outFields: "gaz_name,gaz_featureclass,state_alpha,county_name,gaz_id,fcode,isunknowncoords",
    returnGeometry: "true",
    outSR: 4326,
    f: "geojson"
  )

  http_get_json(uri).fetch("features", [])
end

def point_coordinate(geometry)
  case geometry.fetch("type")
  when "Point"
    geometry.fetch("coordinates")
  when "MultiPoint"
    geometry.fetch("coordinates").first
  else
    raise "Unsupported GNIS geometry type: #{geometry.fetch("type")}"
  end
end

def dedupe_features(features)
  features.each_with_object({}) do |feature, by_key|
    properties = feature.fetch("properties", {})
    coordinate = point_coordinate(feature.fetch("geometry")).map { |value| value.to_f.round(8) }
    key = [properties["gaz_id"], properties["gaz_name"], coordinate].join(":")
    by_key[key] ||= feature
  end.values
end

def distance_squared(point, other)
  ((point[0] - other[0])**2) + ((point[1] - other[1])**2)
end

def best_feature(features, center)
  features
    .map { |feature| [feature, point_coordinate(feature.fetch("geometry"))] }
    .min_by { |_feature, coordinate| distance_squared(coordinate, center) }
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

def buffered_coordinates(factory, coordinate, radius_meters, origin)
  x, y = project_coordinate(coordinate[0].to_f, coordinate[1].to_f, origin)
  multipolygon_coordinates(factory.point(x, y).buffer(radius_meters), origin)
end

def generated_feature(group)
  factory = geos_factory
  radius_meters = group.fetch(:radius_miles) * METERS_PER_MILE
  selected = []
  missing = []

  group.fetch(:features).each do |feature_config|
    matches = dedupe_features(query_gnis(feature_config, group.fetch(:bbox)))
    selected_feature, coordinate = best_feature(matches, group.fetch(:center))

    if selected_feature && coordinate
      properties = selected_feature.fetch("properties", {})
      selected << {
        feature_name: feature_config.fetch(:name),
        selected_name: properties["gaz_name"],
        feature_class: properties["gaz_featureclass"],
        state_alpha: properties["state_alpha"],
        county_name: properties["county_name"],
        gaz_id: properties["gaz_id"],
        fcode: properties["fcode"],
        candidate_count: matches.length,
        source_geometry_type: selected_feature.dig("geometry", "type"),
        source_coordinate: coordinate.map { |value| value.to_f.round(6) },
        buffered_coordinates: buffered_coordinates(factory, coordinate, radius_meters, group.fetch(:center))
      }
    else
      missing << feature_config.fetch(:name)
    end
  end

  {
    "type" => "Feature",
    "properties" => {
      "slug" => group.fetch(:slug),
      "title" => group.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "derived_gnis_feature_buffer",
      "geometry_accuracy" => "approximate",
      "buffer_radius_miles" => group.fetch(:radius_miles),
      "buffer_radius_feet" => (group.fetch(:radius_miles) * 5280).round,
      "source_url" => group.fetch(:source_url),
      "gnis_layer_url" => GNIS_BASE_URL,
      "selected_features" => selected.map { |feature| feature.except(:buffered_coordinates) },
      "missing_features" => missing,
      "notes" => "Derived from official USGS GNIS named-feature points; buffers are approximate planning polygons, not surveyed legal boundaries."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => selected.flat_map { |feature| feature.fetch(:buffered_coordinates) }
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

requested_slugs = ENV.fetch("LOCALIZED_GEOMETRY_SLUGS", "").split(",").map(&:strip).reject(&:empty?)
groups = requested_slugs.empty? ? GROUPS : GROUPS.select { |group| requested_slugs.include?(group.fetch(:slug)) }
missing_slugs = requested_slugs - groups.map { |group| group.fetch(:slug) }
raise "Unknown point-buffer geometry slug(s): #{missing_slugs.join(", ")}" if missing_slugs.any?

groups.each do |group|
  feature = generated_feature(group)
  path = File.join(OUTPUT_DIR, "#{group.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.dig("properties", "selected_features").length} buffers; missing #{feature.dig("properties", "missing_features").length}."
end
