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
NHD_WATERBODY_QUERY_URL = "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/12/query"
METERS_PER_MILE = 1609.344
EARTH_RADIUS_METERS = 6_378_137.0
BUFFER_RESOLUTION = 12

GROUPS = [
  {
    slug: "fremont-winema-gearhart-blue-lake-200-foot-campfire-buffer",
    title: "Gearhart Mountain Blue Lake 200-foot campfire buffer",
    source_url: "https://www.fs.usda.gov/r06/fremont-winema/wilderness",
    radius_miles: 0.0378788,
    bbox: [-120.93, 42.45, -120.75, 42.6],
    center: [-120.84, 42.52],
    lakes: [
      "Blue Lake"
    ]
  },
  {
    slug: "mt-baker-snoqualmie-glacier-peak-quarter-mile-image-byrne-lakes",
    title: "Glacier Peak Image Lake and Lake Byrne 1/4-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/mbs/recreation/glacier-peak-wilderness-mt-baker-snoqualmie",
    radius_miles: 0.25,
    bbox: [-121.35, 48.0, -120.9, 48.28],
    center: [-121.12, 48.15],
    lakes: [
      "Image Lake",
      "Lake Byrne"
    ]
  },
  {
    slug: "okanogan-wenatchee-glacier-peak-200-foot-holden-lyman-lakes",
    title: "Glacier Peak Holden and Lyman Lakes 200-foot campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/recreation/glacier-peak-wilderness-okanogan-wenatchee",
    radius_miles: 0.0378788,
    bbox: [-121.0, 48.12, -120.75, 48.28],
    center: [-120.88, 48.21],
    lakes: [
      "Holden Lake",
      "Lyman Lake"
    ]
  },
  {
    slug: "mt-baker-snoqualmie-henry-jackson-quarter-mile-named-lakes",
    title: "Henry M. Jackson west-side named lake 1/4-mile campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/mbs/recreation/henry-m-jackson-wilderness-mt-baker-snoqualmie",
    radius_miles: 0.25,
    bbox: [-121.5, 47.88, -121.25, 48.08],
    center: [-121.37, 47.98],
    lakes: [
      {name: "Goat Lake", aliases: ["Goat Lake"], center: [-121.3508, 48.0167]},
      {name: "Silver Lake", aliases: ["Silver Lake"], center: [-121.4083, 47.9732]},
      {name: "Upper Twin Lake", aliases: ["Twin Lakes"], center: [-121.3773, 47.9533]},
      {name: "Lower Twin Lake", aliases: ["Twin Lakes"], center: [-121.3768, 47.9494]}
    ]
  },
  {
    slug: "mt-baker-snoqualmie-boulder-river-200-foot-bandana-saddle-lakes",
    title: "Boulder River Bandana and Saddle Lakes 200-foot campfire buffers",
    source_url: "https://www.fs.usda.gov/r06/mbs/recreation/boulder-river-wilderness",
    radius_miles: 0.0378788,
    bbox: [-121.85, 48.12, -121.68, 48.24],
    center: [-121.76, 48.18],
    lakes: [
      "Bandana Lake",
      "Saddle Lake"
    ]
  },
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
      {name: "Upper Ice Lake", aliases: ["Ice Lakes", "Ice Lake", "Upper Ice Lake", "Lower Ice Lake"], center: [-120.7954, 48.1318]},
      {name: "Lower Ice Lake", aliases: ["Ice Lakes", "Ice Lake", "Upper Ice Lake", "Lower Ice Lake"], center: [-120.7837, 48.1333]}
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
  },
  {
    slug: "mt-hood-burnt-lake-half-mile-campfire-buffer",
    title: "Burnt Lake 1/2-mile campfire buffer",
    source_url: "https://wilderness.net/visit-wilderness/?ID=374#area-management",
    radius_miles: 0.5,
    bbox: [-122.1, 45.25, -121.55, 45.55],
    center: [-121.82, 45.39],
    lakes: [
      "Burnt Lake"
    ]
  },
  {
    slug: "mt-hood-wahtum-lake-200-foot-campfire-buffer",
    title: "Wahtum Lake 200-foot campfire buffer",
    source_url: "https://wilderness.net/visit-wilderness/?ID=342#area-management",
    radius_miles: 0.0378788,
    bbox: [-122.0, 45.45, -121.6, 45.65],
    center: [-121.79, 45.58],
    lakes: [
      "Wahtum Lake"
    ]
  },
  {
    slug: "gifford-pinchot-william-o-douglas-quarter-mile-dewey-lakes",
    title: "William O. Douglas Dewey Lakes 1/4-mile campfire buffer",
    source_url: "https://www.fs.usda.gov/media/151852",
    radius_miles: 0.25,
    bbox: [-121.6, 46.55, -120.95, 47.0],
    center: [-121.38, 46.78],
    lakes: [
      {name: "Dewey Lakes", aliases: ["Dewey Lakes", "Dewey Lake"]}
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

def lake_center(lake, group)
  return group.fetch(:center) unless lake.is_a?(Hash)

  lake.fetch(:center, group.fetch(:center))
end

def coordinate_pairs(value, pairs = [])
  if value.is_a?(Array) && value.length >= 2 && value[0].is_a?(Numeric) && value[1].is_a?(Numeric)
    pairs << [value[0].to_f, value[1].to_f]
  elsif value.is_a?(Array)
    value.each { |item| coordinate_pairs(item, pairs) }
  end

  pairs
end

def geometry_center(geometry)
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
    .filter_map { |feature| [feature, geometry_center(feature.fetch("geometry"))] if feature["geometry"] }
    .min_by { |_feature, point| distance_squared(point, center) }
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
    raise "Unsupported NHD waterbody geometry type: #{geometry.fetch("type")}"
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

def buffered_coordinates(factory, feature, radius_meters, origin)
  geometry = geometry_from_geojson(factory, feature.fetch("geometry"), origin)
  multipolygon_coordinates(geometry.buffer(radius_meters), origin)
end

def generated_feature(group)
  factory = geos_factory
  radius_meters = group.fetch(:radius_miles) * METERS_PER_MILE
  selected = []
  missing = []

  group.fetch(:lakes).each do |lake|
    features = dedupe_features(lake_aliases(lake).flat_map { |name| query_waterbody(name, group.fetch(:bbox)) })
    best = best_feature(features, lake_center(lake, group))

    if best
      feature, center = best
      selected << {
        lake_name: lake_name(lake),
        selected_name: feature.dig("properties", "GNIS_NAME"),
        permanent_identifier: feature.dig("properties", "PERMANENT_IDENTIFIER"),
        gnis_id: feature.dig("properties", "GNIS_ID"),
        area_sq_km: feature.dig("properties", "AREASQKM"),
        candidate_count: features.length,
        source_geometry_type: feature.dig("geometry", "type"),
        buffered_coordinates: buffered_coordinates(factory, feature, radius_meters, center)
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
      "geometry_source_type" => "derived_nhd_waterbody_buffer",
      "geometry_accuracy" => "approximate",
      "buffer_radius_miles" => group.fetch(:radius_miles),
      "source_url" => group.fetch(:source_url),
      "nhd_layer_url" => "https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/12",
      "selected_lakes" => selected.map { |lake| lake.except(:buffered_coordinates) },
      "missing_lakes" => missing,
      "notes" => "Derived from official NHD waterbody polygons; buffers are approximate and require reviewer spot checks before relying on exact boundaries."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => selected.flat_map { |lake| lake.fetch(:buffered_coordinates) }
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
