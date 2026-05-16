#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

ROOT = File.expand_path("../..", __dir__)
OUTPUT_DIR = File.join(ROOT, "data/fire_restrictions/localized_geometries")
NHD_WATERBODY_QUERY_URL = "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/12/query"
METERS_PER_MILE = 1609.344
METERS_PER_DEGREE_LATITUDE = 111_320.0

GROUPS = [
  {
    slug: "wallowa-whitman-eagle-cap-quarter-mile-named-lakes",
    title: "Eagle Cap named lake 1/4-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/wallowa-whitman/recreation/eagle-cap-wilderness",
    radius_miles: 0.25,
    bbox: [-118.0, 44.75, -116.7, 45.45],
    center: [-117.35, 45.18],
    lakes: [
      "Bear Lake",
      "Chimney Lake",
      "Eagle Lake",
      {name: "Laverty Lake", aliases: ["Laverty Lake", "Laverty Lakes"]},
      "Mirror Lake",
      "Glacier Lake",
      "Moccasin Lake",
      "Steamboat Lake",
      "Sunshine Lake",
      "Swamp Lake",
      "Prospect Lake",
      "Ice Lake",
      "Hobo Lake",
      "Frazier Lake",
      "Little Frazier Lake",
      "Maxwell Lake",
      "Tombstone Lake",
      "Dollar Lake",
      "Traverse Lake",
      "Jewett Lake",
      "Blue Lake",
      {name: "Upper Lake", aliases: ["Upper Lake"]}
    ]
  },
  {
    slug: "okanogan-wenatchee-alpine-lakes-half-mile-named-lakes",
    title: "Alpine Lakes named lake 1/2-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect",
    radius_miles: 0.5,
    bbox: [-121.7, 47.2, -120.45, 47.95],
    center: [-121.05, 47.55],
    lakes: [
      "Hope Lake",
      "Josephine Lake",
      {name: "Leland Lake", aliases: ["Leland Lake", "Lake Leland"]},
      "Little Eightmile Lake",
      "Mig Lake",
      "Nada Lake",
      "Swimming Deer Lake",
      "Square Lake",
      "Trout Lake",
      {name: "Wolverine Lake", aliases: ["Wolverine Lake", "Lake Wolverine"]},
      "Upper Grace Lake",
      {name: "Lower Grace Lake", aliases: ["Lower Grace Lake", "Grace Lakes"]},
      {name: "Donald Lake", aliases: ["Donald Lake", "Lake Donald"]},
      {name: "Loch Eileen", aliases: ["Loch Eileen", "Eileen Lake"]},
      {name: "Ethel Lake", aliases: ["Ethel Lake", "Lake Ethel"]},
      {name: "Julius Lake", aliases: ["Julius Lake", "Lake Julius"]},
      {name: "Susan Jane Lake", aliases: ["Susan Jane Lake", "Lake Susan Jane"]},
      "Rachel Lake",
      "Upper Park Lake",
      "Glacier Lake",
      "Spectacle Lake",
      {name: "Ivanhoe Lake", aliases: ["Ivanhoe Lake", "Lake Ivanhoe"]},
      "Shovel Lake",
      {name: "Rebecca Lake", aliases: ["Rebecca Lake", "Lake Rebecca"]},
      {name: "Rowena Lake", aliases: ["Rowena Lake", "Lake Rowena"]},
      "Deep Lake"
    ]
  },
  {
    slug: "okanogan-wenatchee-henry-jackson-quarter-mile-named-lakes",
    title: "Henry M. Jackson named lake 1/4-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect",
    radius_miles: 0.25,
    bbox: [-121.55, 47.55, -120.65, 48.18],
    center: [-121.12, 47.85],
    lakes: [
      {name: "Sally Ann Lake", aliases: ["Sally Ann Lake", "Lake Sally Ann"]},
      "Minotaur Lake",
      "Theseus Lake",
      "Heather Lake",
      "Glasses Lake",
      {name: "Valhalla Lake", aliases: ["Valhalla Lake", "Lake Valhalla"]}
    ]
  },
  {
    slug: "okanogan-wenatchee-glacier-peak-half-mile-ice-lakes",
    title: "Glacier Peak Ice Lakes 1/2-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect",
    radius_miles: 0.5,
    bbox: [-121.35, 47.8, -120.25, 48.65],
    center: [-120.85, 48.2],
    lakes: [
      {name: "Ice Lakes", aliases: ["Ice Lakes", "Ice Lake", "Upper Ice Lake", "Lower Ice Lake"]}
    ]
  },
  {
    slug: "okanogan-wenatchee-william-o-douglas-quarter-mile-named-lakes",
    title: "William O. Douglas named lake 1/4-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect",
    radius_miles: 0.25,
    bbox: [-121.75, 46.35, -120.85, 47.1],
    center: [-121.35, 46.68],
    lakes: [
      "Dewey Lake",
      "Goat Lake"
    ]
  },
  {
    slug: "gifford-pinchot-goat-rocks-quarter-mile-named-lakes",
    title: "Goat Rocks named lake campfire buffer candidates",
    source_url: "https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations",
    radius_miles: 0.25,
    bbox: [-121.75, 46.25, -120.9, 46.75],
    center: [-121.35, 46.5],
    lakes: [
      "Goat Lake",
      "Shoe Lake"
    ]
  }
].freeze

def query_waterbody(name, bbox)
  uri = URI(NHD_WATERBODY_QUERY_URL)
  uri.query = URI.encode_www_form(
    where: "GNIS_NAME = '#{name.gsub("'", "''")}'",
    geometry: bbox.join(","),
    geometryType: "esriGeometryEnvelope",
    inSR: 4326,
    spatialRel: "esriSpatialRelIntersects",
    outFields: "GNIS_NAME,GNIS_ID,PERMANENT_IDENTIFIER,AREASQKM,FCODE",
    returnGeometry: "true",
    outSR: 4326,
    f: "geojson"
  )

  http_get_json(uri).fetch("features", [])
end

def http_get_json(uri)
  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 10,
    read_timeout: 30,
    use_ssl: uri.scheme == "https"
  ) { |http| http.get(uri.request_uri) }

  raise "Geometry request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def lake_name(lake)
  lake.is_a?(Hash) ? lake.fetch(:name) : lake
end

def lake_aliases(lake)
  return [lake] unless lake.is_a?(Hash)

  lake.fetch(:aliases, [lake.fetch(:name)])
end

def coordinate_pairs(value, pairs = [])
  if value.is_a?(Array) && value.length >= 2 && value[0].is_a?(Numeric) && value[1].is_a?(Numeric)
    pairs << [value[0].to_f, value[1].to_f]
  elsif value.is_a?(Array)
    value.each { |item| coordinate_pairs(item, pairs) }
  end

  pairs
end

def centroid(geometry)
  pairs = coordinate_pairs(geometry.fetch("coordinates", []))
  return unless pairs.any?

  [
    pairs.sum(&:first) / pairs.length,
    pairs.sum(&:last) / pairs.length
  ]
end

def distance_squared(point, other)
  ((point[0] - other[0])**2) + ((point[1] - other[1])**2)
end

def dedupe_features(features)
  features.each_with_object({}) do |feature, by_id|
    properties = feature.fetch("properties", {})
    key = properties["PERMANENT_IDENTIFIER"] || properties["GNIS_ID"] || "#{properties["GNIS_NAME"]}-#{feature.hash}"
    by_id[key] ||= feature
  end.values
end

def best_feature(features, center)
  features
    .filter_map { |feature| [feature, centroid(feature.fetch("geometry"))] if feature["geometry"] }
    .min_by { |_feature, point| distance_squared(point, center) }
end

def circle_ring(center, radius_meters, segments: 72)
  lon, lat = center
  lat_radius = radius_meters / METERS_PER_DEGREE_LATITUDE
  lon_radius = radius_meters / (METERS_PER_DEGREE_LATITUDE * Math.cos(lat * Math::PI / 180.0))

  ring = (0...segments).map do |index|
    angle = (2.0 * Math::PI * index) / segments
    [
      (lon + (Math.cos(angle) * lon_radius)).round(6),
      (lat + (Math.sin(angle) * lat_radius)).round(6)
    ]
  end
  ring << ring.first
  ring
end

def generated_feature(group)
  radius_meters = group.fetch(:radius_miles) * METERS_PER_MILE
  selected = []
  missing = []

  group.fetch(:lakes).each do |lake|
    features = dedupe_features(lake_aliases(lake).flat_map { |name| query_waterbody(name, group.fetch(:bbox)) })
    best = best_feature(features, group.fetch(:center))

    if best
      feature, center = best
      selected << {
        lake_name: lake_name(lake),
        selected_name: feature.dig("properties", "GNIS_NAME"),
        permanent_identifier: feature.dig("properties", "PERMANENT_IDENTIFIER"),
        gnis_id: feature.dig("properties", "GNIS_ID"),
        area_sq_km: feature.dig("properties", "AREASQKM"),
        candidate_count: features.length,
        center: center
      }
    else
      missing << lake_name(lake)
    end
  end

  {
    "type" => "Feature",
    "properties" => {
      "slug" => group.fetch(:slug),
      "title" => group.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "derived_nhd_centroid_buffer",
      "geometry_accuracy" => "approximate",
      "buffer_radius_miles" => group.fetch(:radius_miles),
      "source_url" => group.fetch(:source_url),
      "nhd_layer_url" => "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/12",
      "selected_lakes" => selected.map { |lake| lake.except(:center) },
      "missing_lakes" => missing,
      "notes" => "Derived from official NHD waterbody centroids; buffers are approximate and require reviewer spot checks before relying on exact boundaries."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => selected.map { |lake| [circle_ring(lake.fetch(:center), radius_meters)] }
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

GROUPS.each do |group|
  feature = generated_feature(group)
  path = File.join(OUTPUT_DIR, "#{group.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.dig("properties", "selected_lakes").length} buffers; missing #{feature.dig("properties", "missing_lakes").length}."
end
