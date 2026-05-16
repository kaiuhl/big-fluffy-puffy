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
DEM_PATH = ENV.fetch("PRISM_DEM_PATH", File.join(ROOT, "tmp/climate/extracted/PRISM_us_dem_800m_bil/PRISM_us_dem_800m_bil.bil"))
DEM_HDR_PATH = ENV.fetch("PRISM_DEM_HDR_PATH", DEM_PATH.sub(/\.bil\z/i, ".hdr"))
WILDERNESS_QUERY_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0/query"
WILDERNESS_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_Wilderness_01/MapServer/0"
PRISM_DEM_URL = "https://prism.oregonstate.edu/downloads/data/PRISM_us_dem_800m_bil.zip"
FT_PER_METER = 3.280839895
EARTH_RADIUS_METERS = 6_378_137.0
BUFFER_RESOLUTION = 4
SIMPLIFY_TOLERANCE_METERS = 80.0
UNION_BATCH_SIZE = 250

TARGETS = [
  {
    slug: "deschutes-central-cascades-above-5700-ft",
    title: "Deschutes Central Cascades wilderness above 5700 feet",
    land_unit_slug: "deschutes",
    threshold_ft: 5700,
    wilderness_names: [
      "Mount Jefferson Wilderness",
      "Mount Washington Wilderness",
      "Three Sisters Wilderness"
    ],
    official_rule_source_url: "https://www.fs.usda.gov/media/144510"
  },
  {
    slug: "willamette-central-cascades-above-5700-ft",
    title: "Willamette Central Cascades wilderness above 5700 feet",
    land_unit_slug: "willamette",
    threshold_ft: 5700,
    wilderness_names: [
      "Mount Jefferson Wilderness",
      "Mount Washington Wilderness",
      "Three Sisters Wilderness"
    ],
    official_rule_source_url: "https://www.fs.usda.gov/media/144510"
  },
  {
    slug: "deschutes-diamond-peak-above-6000-ft",
    title: "Deschutes Diamond Peak Wilderness above 6000 feet",
    land_unit_slug: "deschutes",
    threshold_ft: 6000,
    wilderness_names: ["Diamond Peak Wilderness"],
    official_rule_source_url: "https://www.fs.usda.gov/media/144510"
  },
  {
    slug: "willamette-diamond-peak-above-6000-ft",
    title: "Willamette Diamond Peak Wilderness above 6000 feet",
    land_unit_slug: "willamette",
    threshold_ft: 6000,
    wilderness_names: ["Diamond Peak Wilderness"],
    official_rule_source_url: "https://www.fs.usda.gov/media/144510"
  },
  {
    slug: "mt-baker-snoqualmie-alpine-lakes-above-4000-ft",
    title: "Mt. Baker-Snoqualmie Alpine Lakes Wilderness above 4000 feet",
    land_unit_slug: "mt-baker-snoqualmie",
    threshold_ft: 4000,
    wilderness_names: ["Alpine Lakes Wilderness"],
    official_rule_source_url: "https://www.fs.usda.gov/sites/nfs/files/r06/okanogan-wenatchee/publication/alerts/Alpine%20Lakes%20Wilderness%20Restrictions%20CO%20%2306-17-1994-001.pdf",
    note: "The forest-boundary intersection is used as the repeatable west-side-of-Cascade-Crest proxy for this standing rule."
  },
  {
    slug: "okanogan-wenatchee-alpine-lakes-above-5000-ft",
    title: "Okanogan-Wenatchee Alpine Lakes Wilderness above 5000 feet",
    land_unit_slug: "okanogan-wenatchee",
    threshold_ft: 5000,
    wilderness_names: ["Alpine Lakes Wilderness"],
    official_rule_source_url: "https://www.fs.usda.gov/r06/okanogan-wenatchee/fire/info/wilderness-area-fire-restrictions-always-effect"
  },
  {
    slug: "olympic-wilderness-above-3500-ft",
    title: "Olympic National Forest wilderness above 3500 feet",
    land_unit_slug: "olympic",
    threshold_ft: 3500,
    wilderness_names: [
      "Buckhorn Wilderness",
      "Colonel Bob Wilderness",
      "Mount Skokomish Wilderness",
      "The Brothers Wilderness",
      "Wonder Mountain Wilderness"
    ],
    official_rule_source_url: "https://www.fs.usda.gov/r06/olympic/wilderness"
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

def query_wilderness(names)
  uri = URI(WILDERNESS_QUERY_URL)
  quoted_names = names.map { |name| "'#{name.gsub("'", "''")}'" }.join(",")
  uri.query = URI.encode_www_form(
    where: "wildernessname IN (#{quoted_names})",
    outFields: "wildernessname,areaid,wid,gis_acres,boundarystatus",
    returnGeometry: "true",
    outSR: 4326,
    geometryPrecision: 5,
    f: "geojson"
  )

  data = http_get_json(uri)
  features = data.fetch("features", [])
  found_names = features.map { |feature| feature.dig("properties", "wildernessname") }
  missing = names - found_names
  raise "Missing USFS wilderness geometries for: #{missing.join(", ")}" unless missing.empty?

  features
end

def load_forest_feature(slug)
  data = JSON.parse(File.read(BOUNDARY_PATH))
  feature = data.fetch("features").find { |candidate| candidate.dig("properties", "slug").to_s == slug.to_s }
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

def intersect_bounds(left, right)
  [
    [left[0], right[0]].max,
    [left[1], right[1]].max,
    [left[2], right[2]].min,
    [left[3], right[3]].min
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

def valid_ring_coordinates?(coordinates)
  pairs = coordinates.map { |coordinate| [coordinate[0].to_f, coordinate[1].to_f] }
  pairs.pop if pairs.length > 1 && pairs.first == pairs.last
  pairs.uniq.length >= 3
end

def polygon_from_coordinates(factory, coordinates, origin)
  return unless valid_ring_coordinates?(coordinates.fetch(0))

  exterior = factory.linear_ring(ring_points(factory, coordinates.fetch(0), origin))
  interiors = coordinates
    .drop(1)
    .select { |ring| valid_ring_coordinates?(ring) }
    .map { |ring| factory.linear_ring(ring_points(factory, ring, origin)) }

  factory.polygon(exterior, interiors)
rescue RGeo::Error::InvalidGeometry
  nil
end

def geometry_from_geojson(factory, geometry, origin)
  case geometry.fetch("type")
  when "Polygon"
    polygon_from_coordinates(factory, geometry.fetch("coordinates"), origin) || factory.collection([])
  when "MultiPolygon"
    factory.multi_polygon(geometry.fetch("coordinates").filter_map { |coordinates| polygon_from_coordinates(factory, coordinates, origin) })
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

def read_dem_header(path)
  File.readlines(path, chomp: true).each_with_object({}) do |line, header|
    key, value = line.split(/\s+/, 2)
    next unless key && value

    header[key.downcase] = value.strip
  end
end

def dem_window(bounds, header)
  ulx = Float(header.fetch("ulxmap"))
  uly = Float(header.fetch("ulymap"))
  xdim = Float(header.fetch("xdim"))
  ydim = Float(header.fetch("ydim"))
  ncols = Integer(header.fetch("ncols"))
  nrows = Integer(header.fetch("nrows"))

  min_lon, min_lat, max_lon, max_lat = bounds
  col_min = [((min_lon - ulx) / xdim).floor - 2, 0].max
  col_max = [((max_lon - ulx) / xdim).ceil + 2, ncols - 1].min
  row_min = [((uly - max_lat) / ydim).floor - 2, 0].max
  row_max = [((uly - min_lat) / ydim).ceil + 2, nrows - 1].min

  [row_min, row_max, col_min, col_max]
end

def cell_polygon(factory, lon, lat, xdim, ydim, origin)
  half_x = xdim / 2.0
  half_y = ydim / 2.0
  coordinates = [
    [lon - half_x, lat - half_y],
    [lon + half_x, lat - half_y],
    [lon + half_x, lat + half_y],
    [lon - half_x, lat + half_y],
    [lon - half_x, lat - half_y]
  ]

  polygon_from_coordinates(factory, [coordinates], origin)
end

def union_geometries(factory, geometries)
  return factory.collection([]) if geometries.empty?

  batches = geometries.each_slice(UNION_BATCH_SIZE).map { |slice| factory.collection(slice).unary_union }
  factory.collection(batches).unary_union
end

def elevation_cells_geometry(factory, clipping_geometry, bounds, header, threshold_ft, origin)
  ulx = Float(header.fetch("ulxmap"))
  uly = Float(header.fetch("ulymap"))
  xdim = Float(header.fetch("xdim"))
  ydim = Float(header.fetch("ydim"))
  ncols = Integer(header.fetch("ncols"))
  nodata = Integer(header.fetch("nodata"))
  row_min, row_max, col_min, col_max = dem_window(bounds, header)
  row_bytes = ncols * 4
  geometries = []
  qualifying_cells = 0

  File.open(DEM_PATH, "rb") do |file|
    (row_min..row_max).each do |row|
      file.seek(row * row_bytes)
      values = file.read(row_bytes).unpack("l<*")
      lat = uly - (row * ydim)

      (col_min..col_max).each do |col|
        meters = values[col]
        next if meters == nodata
        next if meters * FT_PER_METER < threshold_ft

        lon = ulx + (col * xdim)
        x, y = project_coordinate(lon, lat, origin)
        point = factory.point(x, y)
        next unless clipping_geometry.contains?(point) || clipping_geometry.touches?(point)

        clipped = cell_polygon(factory, lon, lat, xdim, ydim, origin).intersection(clipping_geometry)
        next if clipped.empty?

        qualifying_cells += 1
        geometries << clipped
      end
    end
  end

  geometry = union_geometries(factory, geometries)
  geometry = geometry.simplify_preserve_topology(SIMPLIFY_TOLERANCE_METERS) unless geometry.empty?

  [geometry, qualifying_cells]
end

def feature_for_target(target)
  factory = geos_factory
  forest_feature = load_forest_feature(target.fetch(:land_unit_slug))
  wilderness_features = query_wilderness(target.fetch(:wilderness_names))
  forest_bounds = bounds_for_features([forest_feature])
  wilderness_bounds = bounds_for_features(wilderness_features)
  bounds = intersect_bounds(forest_bounds, wilderness_bounds)
  origin = bounds_center(bounds)
  forest_geometry = clean_geometry(geometry_from_geojson(factory, forest_feature.fetch("geometry"), origin))
  wilderness_geometry = clean_geometry(union_geometries(
    factory,
    wilderness_features.map { |feature| clean_geometry(geometry_from_geojson(factory, feature.fetch("geometry"), origin)) }
  ))
  clipping_geometry = clean_geometry(forest_geometry.intersection(wilderness_geometry))
  raise "No forest/wilderness overlap for #{target.fetch(:slug)}" if clipping_geometry.empty?

  header = read_dem_header(DEM_HDR_PATH)
  elevation_geometry, qualifying_cells = elevation_cells_geometry(
    factory,
    clipping_geometry,
    bounds,
    header,
    target.fetch(:threshold_ft),
    origin
  )
  coordinates = multipolygon_coordinates(elevation_geometry, origin)

  raise "No DEM cells matched #{target.fetch(:slug)}" if coordinates.empty?

  {
    "type" => "Feature",
    "properties" => {
      "slug" => target.fetch(:slug),
      "title" => target.fetch(:title),
      "land_unit_slug" => target.fetch(:land_unit_slug),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "derived_dem_elevation",
      "geometry_accuracy" => "approximate",
      "elevation_threshold_ft" => target.fetch(:threshold_ft),
      "elevation_source" => "PRISM 800m DEM supporting dataset aligned to PRISM normals grid",
      "elevation_source_url" => PRISM_DEM_URL,
      "wilderness_source_url" => WILDERNESS_LAYER_URL,
      "forest_boundary_source_url" => forest_feature.dig("properties", "source_url"),
      "official_rule_source_url" => target.fetch(:official_rule_source_url),
      "wilderness_names" => target.fetch(:wilderness_names),
      "qualifying_dem_cell_count" => qualifying_cells,
      "simplify_tolerance_meters" => SIMPLIFY_TOLERANCE_METERS,
      "notes" => [
        "Derived from PRISM 800m DEM cells intersected with USFS EDW wilderness boundaries and BFP forest boundaries.",
        "This is an approximate planning map, not a surveyed legal order boundary.",
        target[:note]
      ].compact.join(" ")
    },
    "geometry" => {
      "type" => "MultiPolygon",
      "coordinates" => coordinates
    }
  }
end

raise "Missing PRISM DEM at #{DEM_PATH}. Run scripts/climate/build_normals.py or set PRISM_DEM_PATH." unless File.file?(DEM_PATH)
raise "Missing PRISM DEM header at #{DEM_HDR_PATH}. Set PRISM_DEM_HDR_PATH." unless File.file?(DEM_HDR_PATH)

FileUtils.mkdir_p(OUTPUT_DIR)

TARGETS.each do |target|
  feature = feature_for_target(target)
  path = File.join(OUTPUT_DIR, "#{target.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path} with #{feature.dig("properties", "qualifying_dem_cell_count")} DEM cells."
end
