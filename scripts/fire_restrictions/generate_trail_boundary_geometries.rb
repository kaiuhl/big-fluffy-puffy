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
TRAIL_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0/query"
TRAIL_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0"
FOREST_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_ForestSystemBoundaries_01/MapServer/0/query"
FOREST_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_ForestSystemBoundaries_01/MapServer/0"
WILDERNESS_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0/query"
WILDERNESS_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0"
EARTH_RADIUS_METERS = 6_378_137.0
BUFFER_RESOLUTION = 4

TARGETS = [
  {
    slug: "gifford-pinchot-mt-adams-high-country-campfire-prohibition-area",
    title: "Mt. Adams Wilderness high-country campfire prohibition area",
    source_url: "https://www.fs.usda.gov/media/202123",
    official_rule_source_url: "https://www.fs.usda.gov/r06/giffordpinchot/wilderness/wilderness-regulations",
    bbox: [-121.8, 46.1, -121.4, 46.42],
    trail_numbers: ["9", "114", "2000"],
    forest_name: "Gifford Pinchot National Forest",
    wilderness_name: "Mount Adams Wilderness"
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

def query_geojson(url, params)
  uri = URI(url)
  uri.query = URI.encode_www_form(params.merge(f: "geojson"))
  http_get_json(uri)
end

def query_trails(target)
  quoted = target.fetch(:trail_numbers).map { |number| "'#{number.gsub("'", "''")}'" }.join(",")
  query_geojson(TRAIL_QUERY_URL,
    where: "trail_no IN (#{quoted})",
    geometry: target.fetch(:bbox).join(","),
    geometryType: "esriGeometryEnvelope",
    inSR: 4326,
    spatialRel: "esriSpatialRelIntersects",
    outFields: "trail_name,trail_no,trail_cn,bmp,emp,segment_length,admin_org,managing_org,gis_miles",
    returnGeometry: "true",
    outSR: 4326)
    .fetch("features", [])
end

def query_forest(target)
  query_geojson(FOREST_QUERY_URL,
    where: "FORESTNAME = '#{target.fetch(:forest_name).gsub("'", "''")}'",
    outFields: "FORESTNAME,FORESTORGCODE,REGION,GIS_ACRES",
    returnGeometry: "true",
    outSR: 4326,
    geometryPrecision: 6)
    .fetch("features")
    .first || raise("Missing forest boundary for #{target.fetch(:forest_name)}")
end

def query_wilderness(target)
  query_geojson(WILDERNESS_QUERY_URL,
    where: "wildernessname = '#{target.fetch(:wilderness_name).gsub("'", "''")}'",
    outFields: "wildernessname,areaid,wid,gis_acres,boundarystatus",
    returnGeometry: "true",
    outSR: 4326,
    geometryPrecision: 6)
    .fetch("features")
    .first || raise("Missing wilderness boundary for #{target.fetch(:wilderness_name)}")
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
    (origin_lon + (x / (EARTH_RADIUS_METERS * Math.cos(origin_lat_radians)) * 180.0 / Math::PI)).round(6),
    (origin_lat + (y / EARTH_RADIUS_METERS * 180.0 / Math::PI)).round(6)
  ]
end

def project_points(points, origin)
  points.map { |lon, lat| project_coordinate(lon, lat, origin) }
end

def unproject_points(points, origin)
  points.map { |x, y| unproject_coordinate(x, y, origin) }
end

def distance_squared(point, other)
  ((point[0] - other[0])**2) + ((point[1] - other[1])**2)
end

def line_coordinates(geometry)
  case geometry.fetch("type")
  when "LineString"
    geometry.fetch("coordinates")
  when "MultiLineString"
    geometry.fetch("coordinates").flatten(1)
  else
    raise "Unsupported trail geometry type: #{geometry.fetch("type")}"
  end
end

def trail_sequence(features, trail_no)
  selected = features.select { |feature| feature.dig("properties", "trail_no").to_s == trail_no.to_s }
  raise "Missing trail #{trail_no}" if selected.empty?

  selected
    .sort_by { |feature| feature.dig("properties", "bmp").to_f }
    .flat_map { |feature| line_coordinates(feature.fetch("geometry")) }
    .each_with_object([]) do |coordinate, coordinates|
      coordinates << coordinate if coordinates.empty? || coordinate != coordinates.last
    end
end

def nearest_on_segment(point, start_point, end_point)
  dx = end_point[0] - start_point[0]
  dy = end_point[1] - start_point[1]
  return [start_point, 0.0] if dx.zero? && dy.zero?

  ratio = ((point[0] - start_point[0]) * dx + (point[1] - start_point[1]) * dy) / ((dx * dx) + (dy * dy))
  ratio = ratio.clamp(0.0, 1.0)
  [[start_point[0] + (ratio * dx), start_point[1] + (ratio * dy)], ratio]
end

def nearest_on_polyline(point, points)
  best = nil
  cumulative = 0.0

  points.each_cons(2).with_index do |(start_point, end_point), index|
    closest, ratio = nearest_on_segment(point, start_point, end_point)
    length = Math.sqrt(distance_squared(start_point, end_point))
    offset = cumulative + (ratio * length)
    distance = distance_squared(point, closest)
    best = {distance: distance, index: index, ratio: ratio, point: closest, offset: offset} if best.nil? || distance < best.fetch(:distance)
    cumulative += length
  end

  best || raise("Cannot snap to empty polyline")
end

def point_at_offset(points, target_offset)
  cumulative = 0.0
  points.each_cons(2) do |start_point, end_point|
    length = Math.sqrt(distance_squared(start_point, end_point))
    if target_offset <= cumulative + length
      ratio = length.zero? ? 0.0 : (target_offset - cumulative) / length
      return [
        start_point[0] + (ratio * (end_point[0] - start_point[0])),
        start_point[1] + (ratio * (end_point[1] - start_point[1]))
      ]
    end
    cumulative += length
  end

  points.last
end

def slice_polyline(points, from_offset, to_offset)
  return slice_polyline(points, to_offset, from_offset).reverse if from_offset > to_offset

  result = [point_at_offset(points, from_offset)]
  cumulative = 0.0
  points.each_cons(2) do |start_point, end_point|
    length = Math.sqrt(distance_squared(start_point, end_point))
    segment_end = cumulative + length

    if segment_end > from_offset && segment_end < to_offset
      result << end_point
    end

    cumulative = segment_end
  end
  result << point_at_offset(points, to_offset)
  dedupe_consecutive_points(result)
end

def dedupe_consecutive_points(points)
  points.each_with_object([]) do |point, unique|
    unique << point if unique.empty? || distance_squared(point, unique.last) > 0.000001
  end
end

def polygon_rings(geometry)
  case geometry.fetch("type")
  when "Polygon"
    geometry.fetch("coordinates")
  when "MultiPolygon"
    geometry.fetch("coordinates").flat_map { |polygon| polygon }
  else
    raise "Unsupported polygon geometry type: #{geometry.fetch("type")}"
  end
end

def boundary_slice(rings, from_point, to_point)
  best = nil

  rings.each_with_index do |ring, ring_index|
    projected = ring
    from_snap = nearest_on_polyline(from_point, projected)
    to_snap = nearest_on_polyline(to_point, projected)
    forward = slice_polyline(projected, from_snap.fetch(:offset), to_snap.fetch(:offset))
    backward = slice_polyline(projected, to_snap.fetch(:offset), from_snap.fetch(:offset)).reverse
    forward_length = polyline_length(forward)
    backward_length = polyline_length(backward)
    candidate = (forward_length <= backward_length) ? forward : backward
    candidate_length = [forward_length, backward_length].min
    best = {ring_index: ring_index, points: candidate, length: candidate_length} if best.nil? || candidate_length < best.fetch(:length)
  end

  best || raise("Cannot slice boundary")
end

def nearest_on_rings(point, rings)
  best = nil

  rings.each_with_index do |ring, ring_index|
    snap = nearest_on_polyline(point, ring).merge(ring_index: ring_index)
    best = snap if best.nil? || snap.fetch(:distance) < best.fetch(:distance)
  end

  best || raise("Cannot snap to empty boundary rings")
end

def polyline_length(points)
  points.each_cons(2).sum { |left, right| Math.sqrt(distance_squared(left, right)) }
end

def geos_factory
  raise "RGeo GEOS support is required. Install GEOS before running this script." unless RGeo::Geos.supported?

  RGeo::Geos.factory(buffer_resolution: BUFFER_RESOLUTION)
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
    raise "Unsupported GeoJSON polygon type: #{geometry.fetch("type")}"
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
  trail_features = query_trails(target)
  forest_feature = query_forest(target)
  wilderness_feature = query_wilderness(target)
  origin = bounds_center(bounds_for_features([forest_feature, wilderness_feature]))

  pct = project_points(trail_sequence(trail_features, "2000"), origin)
  highline = project_points(trail_sequence(trail_features, "114"), origin)
  round_the_mountain = project_points(trail_sequence(trail_features, "9"), origin)
  boundary_rings = polygon_rings(forest_feature.fetch("geometry")).map { |ring| project_points(ring, origin) }

  pct_to_highline = nearest_on_polyline(highline.first, pct)
  pct_to_round = nearest_on_polyline(round_the_mountain.last, pct)
  pct_segment = slice_polyline(pct, pct_to_round.fetch(:offset), pct_to_highline.fetch(:offset))

  highline_boundary = nearest_on_rings(highline.last, boundary_rings)
  round_boundary = nearest_on_rings(round_the_mountain.first, boundary_rings)
  boundary_candidates = if highline_boundary.fetch(:ring_index) == round_boundary.fetch(:ring_index)
    [boundary_rings.fetch(highline_boundary.fetch(:ring_index))]
  else
    boundary_rings
  end
  boundary_segment = boundary_slice(boundary_candidates, highline_boundary.fetch(:point), round_boundary.fetch(:point)).fetch(:points)

  ring = dedupe_consecutive_points(
    pct_segment +
      [highline.first] +
      highline +
      [highline_boundary.fetch(:point)] +
      boundary_segment +
      [round_boundary.fetch(:point), round_the_mountain.first] +
      round_the_mountain +
      [pct_to_round.fetch(:point)]
  )

  ring << ring.first unless ring.first == ring.last
  coordinates = [unproject_points(ring, origin)]
  factory = geos_factory
  raw_geometry = clean_geometry(polygon_from_coordinates(factory, coordinates, origin))
  forest_geometry = clean_geometry(geometry_from_geojson(factory, forest_feature.fetch("geometry"), origin))
  wilderness_geometry = clean_geometry(geometry_from_geojson(factory, wilderness_feature.fetch("geometry"), origin))
  clipped_geometry = clean_geometry(raw_geometry.intersection(forest_geometry).intersection(wilderness_geometry))
  clipped_coordinates = multipolygon_coordinates(clipped_geometry, origin)

  raise "Generated geometry is empty for #{target.fetch(:slug)}" if clipped_coordinates.empty?

  selected_trails = trail_features.map do |feature|
    properties = feature.fetch("properties")
    properties.slice("trail_name", "trail_no", "trail_cn", "bmp", "emp", "segment_length", "admin_org", "managing_org", "gis_miles")
  end

  {
    "type" => "Feature",
    "properties" => {
      "slug" => target.fetch(:slug),
      "title" => target.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "derived_usfs_trail_boundary_polygon",
      "geometry_accuracy" => "approximate",
      "source_url" => target.fetch(:source_url),
      "official_rule_source_url" => target.fetch(:official_rule_source_url),
      "trail_source_url" => TRAIL_LAYER_URL,
      "forest_boundary_source_url" => FOREST_LAYER_URL,
      "wilderness_source_url" => WILDERNESS_LAYER_URL,
      "forest_name" => forest_feature.dig("properties", "forestname") || target.fetch(:forest_name),
      "wilderness_name" => wilderness_feature.dig("properties", "wildernessname") || target.fetch(:wilderness_name),
      "selected_trails" => selected_trails,
      "boundary_snap_notes" => {
        "pct_to_highline_distance_meters" => Math.sqrt(pct_to_highline.fetch(:distance)).round(2),
        "pct_to_round_the_mountain_distance_meters" => Math.sqrt(pct_to_round.fetch(:distance)).round(2),
        "highline_to_forest_boundary_distance_meters" => Math.sqrt(highline_boundary.fetch(:distance)).round(2),
        "round_the_mountain_to_forest_boundary_distance_meters" => Math.sqrt(round_boundary.fetch(:distance)).round(2)
      },
      "notes" => "Derived from official USFS trail centerlines, forest boundary, and wilderness boundary, then clipped to the official Mount Adams Wilderness polygon. The result approximates the official PDF map, not a surveyed legal boundary."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => clipped_coordinates
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

requested_slugs = ENV.fetch("LOCALIZED_GEOMETRY_SLUGS", "").split(",").map(&:strip).reject(&:empty?)
targets = requested_slugs.empty? ? TARGETS : TARGETS.select { |target| requested_slugs.include?(target.fetch(:slug)) }
missing_slugs = requested_slugs - targets.map { |target| target.fetch(:slug) }
raise "Unknown trail-boundary geometry slug(s): #{missing_slugs.join(", ")}" if missing_slugs.any?

targets.each do |target|
  feature = generated_feature(target)
  path = File.join(OUTPUT_DIR, "#{target.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.fetch("geometry").fetch("coordinates").length} polygon part(s)."
end
