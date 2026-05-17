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
TRAIL_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0/query"
TRAIL_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0"
WILDERNESS_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0/query"
WILDERNESS_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0"
EARTH_RADIUS_METERS = 6_378_137.0
METERS_PER_MILE = 1609.344
BUFFER_RESOLUTION = 12

TARGETS = [
  {
    slug: "mt-hood-wilderness-named-area-campfire-affected-area-envelopes",
    title: "Mount Hood Wilderness named-area campfire affected-area envelopes",
    source_url: "https://www.fs.usda.gov/media/234596",
    official_trail_page_url: "https://www.fs.usda.gov/r06/mthood/recreation/trails/timberline-trail-600",
    linked_from_source_url: "https://www.fs.usda.gov/r06/mthood/fire",
    bbox: [-121.95, 45.25, -121.5, 45.48],
    center: [-121.74, 45.39],
    wilderness_name: "Mount Hood Wilderness",
    explicit_point_buffers: [
      {
        name: "Ramona Falls",
        layer_id: 4,
        feature_class: "Falls",
        state_alpha: "OR",
        radius_miles: 500.0 / 5280.0,
        restriction_detail: "Campfires are prohibited within 500 feet of Ramona Falls."
      },
      {
        name: "McNeil Point",
        layer_id: 2,
        feature_class: "Ridge",
        state_alpha: "OR",
        radius_miles: 500.0 / 5280.0,
        restriction_detail: "Campfires are prohibited within 500 feet of McNeil Point."
      }
    ],
    named_place_envelopes: [
      {
        name: "Elk Cove",
        layer_id: 2,
        feature_class: "Basin",
        state_alpha: "OR",
        radius_miles: 0.5,
        restriction_detail: "Campfires are prohibited within the tree-covered island in Elk Cove."
      }
    ],
    trail_envelopes: [
      {
        name: "Elk Meadows",
        trail_name: "ELK MEADOWS PERIMETER",
        trail_no: "645A",
        radius_miles: 0.2,
        restriction_detail: "Campfires are prohibited within the tree-covered island in Elk Meadows."
      },
      {
        name: "Paradise Park",
        trail_name: "PARADISE PARK LOOP",
        trail_no: "757",
        radius_miles: 0.3,
        restriction_detail: "Campfires are prohibited within Paradise Park."
      }
    ]
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

def query_gnis(feature, bbox)
  query_geojson("#{GNIS_BASE_URL}/#{feature.fetch(:layer_id)}/query",
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
    outSR: 4326)
    .fetch("features", [])
end

def query_trail(trail, bbox)
  query_geojson(TRAIL_QUERY_URL,
    where: [
      "trail_no = '#{trail.fetch(:trail_no).gsub("'", "''")}'",
      "trail_name = '#{trail.fetch(:trail_name).gsub("'", "''")}'"
    ].join(" AND "),
    geometry: bbox.join(","),
    geometryType: "esriGeometryEnvelope",
    inSR: 4326,
    spatialRel: "esriSpatialRelIntersects",
    outFields: "trail_name,trail_no,trail_cn,bmp,emp,segment_length,admin_org,managing_org,gis_miles",
    returnGeometry: "true",
    outSR: 4326)
    .fetch("features", [])
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

def line_strings_from_geojson(factory, geometry, origin)
  case geometry.fetch("type")
  when "LineString"
    [factory.line_string(geometry.fetch("coordinates").map { |lon, lat| factory.point(*project_coordinate(lon.to_f, lat.to_f, origin)) })]
  when "MultiLineString"
    geometry.fetch("coordinates").map do |coordinates|
      factory.line_string(coordinates.map { |lon, lat| factory.point(*project_coordinate(lon.to_f, lat.to_f, origin)) })
    end
  else
    raise "Unsupported trail geometry type: #{geometry.fetch("type")}"
  end
end

def point_buffer_geometry(factory, coordinate, radius_miles, origin)
  x, y = project_coordinate(coordinate[0].to_f, coordinate[1].to_f, origin)
  factory.point(x, y).buffer(radius_miles * METERS_PER_MILE)
end

def trail_buffer_geometry(factory, trail_features, radius_miles, origin)
  parts = trail_features.flat_map { |feature| line_strings_from_geojson(factory, feature.fetch("geometry"), origin) }
  raise "Cannot buffer empty trail geometry." if parts.empty?

  clean_geometry(factory.collection(parts).buffer(radius_miles * METERS_PER_MILE))
end

def selected_gnis_metadata(config, selected_feature, coordinate, candidate_count)
  properties = selected_feature.fetch("properties", {})
  {
    "feature_name" => config.fetch(:name),
    "selected_name" => properties["gaz_name"],
    "feature_class" => properties["gaz_featureclass"],
    "state_alpha" => properties["state_alpha"],
    "county_name" => properties["county_name"],
    "gaz_id" => properties["gaz_id"],
    "fcode" => properties["fcode"],
    "candidate_count" => candidate_count,
    "source_geometry_type" => selected_feature.dig("geometry", "type"),
    "source_coordinate" => coordinate.map { |value| value.to_f.round(6) },
    "buffer_radius_miles" => config.fetch(:radius_miles),
    "restriction_detail" => config[:restriction_detail]
  }.compact
end

def selected_trail_metadata(config, trail_features)
  {
    "area_name" => config.fetch(:name),
    "trail_name" => config.fetch(:trail_name),
    "trail_no" => config.fetch(:trail_no),
    "buffer_radius_miles" => config.fetch(:radius_miles),
    "restriction_detail" => config.fetch(:restriction_detail),
    "selected_segments" => trail_features.map do |feature|
      feature.fetch("properties").slice("trail_name", "trail_no", "trail_cn", "bmp", "emp", "segment_length", "admin_org", "managing_org", "gis_miles")
    end
  }
end

def gnis_map_subfeature(config, metadata, source_kind:)
  radius_feet = (config.fetch(:radius_miles) * 5280).round
  shape_label = (source_kind == "explicit_buffer") ? "buffer" : "envelope"
  detail = config.fetch(:restriction_detail)
  detail = "Affected-area envelope. #{detail}" if source_kind == "affected_area_envelope" && !detail.start_with?("Affected-area envelope.")

  {
    "part_name" => config.fetch(:name),
    "source_kind" => source_kind,
    "restriction_detail" => detail,
    "geometry_basis" => "#{radius_feet}-foot #{shape_label} around the USGS GNIS named-feature point for #{metadata.fetch("selected_name")} (#{metadata.fetch("feature_class")})",
    "source_coordinate" => metadata.fetch("source_coordinate"),
    "buffer_radius_miles" => config.fetch(:radius_miles)
  }
end

def trail_map_subfeature(config)
  radius_feet = (config.fetch(:radius_miles) * 5280).round
  detail = config.fetch(:restriction_detail)
  detail = "Affected-area envelope. #{detail}" if !detail.start_with?("Affected-area envelope.") && config.fetch(:name) != "Paradise Park"

  {
    "part_name" => config.fetch(:name),
    "source_kind" => "affected_area_envelope",
    "restriction_detail" => detail,
    "geometry_basis" => "#{radius_feet}-foot envelope around USFS #{config.fetch(:trail_name).split.map(&:capitalize).join(" ")} Trail ##{config.fetch(:trail_no)}",
    "trail_name" => config.fetch(:trail_name),
    "trail_no" => config.fetch(:trail_no),
    "buffer_radius_miles" => config.fetch(:radius_miles)
  }
end

def append_map_subfeature!(factory, wilderness_geometry, geometry, metadata, polygon_parts, map_subfeatures, origin)
  clipped = clean_geometry(clean_geometry(geometry).intersection(wilderness_geometry))
  coordinates = multipolygon_coordinates(clipped, origin)
  return if coordinates.empty?

  first_index = polygon_parts.length
  polygon_parts.concat(coordinates)
  map_subfeatures << metadata.merge("geometry_part_indexes" => (first_index...(first_index + coordinates.length)).to_a)
end

def generated_feature(target)
  factory = geos_factory
  wilderness_feature = query_wilderness(target)
  origin = bounds_center(bounds_for_features([wilderness_feature]))
  wilderness_geometry = clean_geometry(geometry_from_geojson(factory, wilderness_feature.fetch("geometry"), origin))
  polygon_parts = []
  map_subfeatures = []
  selected_explicit_buffers = []
  selected_named_place_envelopes = []
  selected_trail_envelopes = []
  missing_features = []
  missing_trails = []

  target.fetch(:explicit_point_buffers).each do |config|
    matches = dedupe_features(query_gnis(config, target.fetch(:bbox)))
    selected_feature, coordinate = best_feature(matches, target.fetch(:center))

    if selected_feature && coordinate
      metadata = selected_gnis_metadata(config, selected_feature, coordinate, matches.length)
      selected_explicit_buffers << metadata
      append_map_subfeature!(
        factory,
        wilderness_geometry,
        point_buffer_geometry(factory, coordinate, config.fetch(:radius_miles), origin),
        gnis_map_subfeature(config, metadata, source_kind: "explicit_buffer"),
        polygon_parts,
        map_subfeatures,
        origin
      )
    else
      missing_features << config.fetch(:name)
    end
  end

  target.fetch(:named_place_envelopes).each do |config|
    matches = dedupe_features(query_gnis(config, target.fetch(:bbox)))
    selected_feature, coordinate = best_feature(matches, target.fetch(:center))

    if selected_feature && coordinate
      metadata = selected_gnis_metadata(config, selected_feature, coordinate, matches.length)
      selected_named_place_envelopes << metadata
      append_map_subfeature!(
        factory,
        wilderness_geometry,
        point_buffer_geometry(factory, coordinate, config.fetch(:radius_miles), origin),
        gnis_map_subfeature(config, metadata, source_kind: "affected_area_envelope"),
        polygon_parts,
        map_subfeatures,
        origin
      )
    else
      missing_features << config.fetch(:name)
    end
  end

  target.fetch(:trail_envelopes).each do |config|
    trail_features = query_trail(config, target.fetch(:bbox))

    if trail_features.any?
      selected_trail_envelopes << selected_trail_metadata(config, trail_features)
      append_map_subfeature!(
        factory,
        wilderness_geometry,
        trail_buffer_geometry(factory, trail_features, config.fetch(:radius_miles), origin),
        trail_map_subfeature(config),
        polygon_parts,
        map_subfeatures,
        origin
      )
    else
      missing_trails << "#{config.fetch(:trail_name)} ##{config.fetch(:trail_no)}"
    end
  end

  raise "Generated geometry is empty for #{target.fetch(:slug)}" if polygon_parts.empty?

  {
    "type" => "Feature",
    "properties" => {
      "slug" => target.fetch(:slug),
      "title" => target.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "affected_area_envelope",
      "geometry_accuracy" => "approximate",
      "geometry_coverage" => "affected_area_envelope",
      "source_url" => target.fetch(:source_url),
      "official_trail_page_url" => target.fetch(:official_trail_page_url),
      "linked_from_source_url" => target.fetch(:linked_from_source_url),
      "gnis_layer_url" => GNIS_BASE_URL,
      "trail_source_url" => TRAIL_LAYER_URL,
      "wilderness_source_url" => WILDERNESS_LAYER_URL,
      "wilderness_name" => wilderness_feature.dig("properties", "wildernessname") || target.fetch(:wilderness_name),
      "selected_explicit_buffers" => selected_explicit_buffers,
      "selected_named_place_envelopes" => selected_named_place_envelopes,
      "selected_trail_envelopes" => selected_trail_envelopes,
      "map_subfeatures" => map_subfeatures,
      "affected_area_envelopes" => ["Elk Cove", "Elk Meadows", "Paradise Park"],
      "missing_features" => missing_features,
      "missing_trails" => missing_trails,
      "notes" => "This combines explicit 500-foot GNIS named-feature buffers with broader affected-area envelopes derived from GNIS named-place points and USFS trail centerlines, clipped to the official Mount Hood Wilderness polygon. The Elk Cove and Elk Meadows polygons are broader than the legal tree-covered-island restriction."
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => polygon_parts
    }
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

requested_slugs = ENV.fetch("LOCALIZED_GEOMETRY_SLUGS", "").split(",").map(&:strip).reject(&:empty?)
targets = requested_slugs.empty? ? TARGETS : TARGETS.select { |target| requested_slugs.include?(target.fetch(:slug)) }
missing_slugs = requested_slugs - targets.map { |target| target.fetch(:slug) }
raise "Unknown affected-area envelope geometry slug(s): #{missing_slugs.join(", ")}" if missing_slugs.any?

targets.each do |target|
  feature = generated_feature(target)
  path = File.join(OUTPUT_DIR, "#{target.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.fetch("geometry").fetch("coordinates").length} polygon part(s)."
end
