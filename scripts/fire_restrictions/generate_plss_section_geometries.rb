#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

ROOT = File.expand_path("../..", __dir__)
OUTPUT_DIR = File.join(ROOT, "data/fire_restrictions/localized_geometries")
BLM_PLSS_SECTION_QUERY_URL = "https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer/2/query"
BLM_PLSS_SECTION_LAYER_URL = "https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer/2"

SECTIONS = [
  {
    slug: "klamath-devils-punchbowl-plss-section-6",
    title: "Devil's Punchbowl Campfire Prohibition Area",
    source_url: "https://www.fs.usda.gov/r05/klamath/alerts/wilderness-area-restrictions-siskiyou-marble-mountain-and-russian-wilderness",
    official_map_url: "https://www.fs.usda.gov/sites/nfs/files/r05/klamath/image/alerts/05-05-00-26-01%20-%20Wilderness%20Maps%20-%20Devils%20Punchbowl.jpg",
    plssid: "CA150160N0050E0",
    section_number: "06",
    meridian: "Humboldt Meridian",
    township_range_label: "T16N R5E HBM",
    affected_area: "Section 6, Township 16 North, Range 5 East, Humboldt Base and Meridian"
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

  raise "PLSS request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def query_section(target)
  uri = URI(BLM_PLSS_SECTION_QUERY_URL)
  uri.query = URI.encode_www_form(
    where: "PLSSID = '#{target.fetch(:plssid)}' AND FRSTDIVNO = '#{target.fetch(:section_number)}'",
    outFields: "OBJECTID,PLSSID,FRSTDIVID,FRSTDIVNO,FRSTDIVLAB,SOURCEREF",
    returnGeometry: "true",
    outSR: 4326,
    geometryPrecision: 6,
    f: "geojson"
  )

  features = http_get_json(uri).fetch("features", [])
  raise "Expected one PLSS section for #{target.fetch(:slug)}, found #{features.length}." unless features.length == 1

  features.first
end

def generated_feature(target)
  section = query_section(target)
  properties = section.fetch("properties")

  {
    "type" => "Feature",
    "properties" => {
      "slug" => target.fetch(:slug),
      "title" => target.fetch(:title),
      "generated_at" => Time.now.utc.iso8601,
      "geometry_source_type" => "blm_plss_section",
      "geometry_accuracy" => "source",
      "source_url" => target.fetch(:source_url),
      "official_map_url" => target.fetch(:official_map_url),
      "blm_layer_url" => BLM_PLSS_SECTION_LAYER_URL,
      "plssid" => properties["PLSSID"],
      "frstdivid" => properties["FRSTDIVID"],
      "section_number" => properties["FRSTDIVNO"],
      "township_range_label" => target.fetch(:township_range_label),
      "meridian" => target.fetch(:meridian),
      "map_subfeatures" => [
        {
          "part_name" => "Devil's Punchbowl Campfire Prohibition Area",
          "source_kind" => "blm_plss_section",
          "restriction_detail" => "Wood fires are prohibited in the Devil's Punchbowl Campfire Prohibition Area.",
          "geometry_basis" => "BLM PLSS section polygon for #{target.fetch(:affected_area)}",
          "geometry_part_indexes" => [0]
        }
      ],
      "notes" => "The Forest Service order defines the prohibition area as this PLSS section and shows the same section on Exhibit A. The Forest Service order remains the legal boundary."
    },
    "geometry" => section.fetch("geometry")
  }
end

FileUtils.mkdir_p(OUTPUT_DIR)

requested_slugs = ENV.fetch("LOCALIZED_GEOMETRY_SLUGS", "").split(",").map(&:strip).reject(&:empty?)
sections = requested_slugs.empty? ? SECTIONS : SECTIONS.select { |target| requested_slugs.include?(target.fetch(:slug)) }
missing_slugs = requested_slugs - sections.map { |target| target.fetch(:slug) }
raise "Unknown localized geometry slug(s): #{missing_slugs.join(", ")}" if missing_slugs.any?

sections.each do |target|
  feature = generated_feature(target)
  path = File.join(OUTPUT_DIR, "#{target.fetch(:slug)}.geojson")
  File.write(path, "#{JSON.pretty_generate(feature)}\n")
  warn "Wrote #{path}."
end
