require "fileutils"
require "json"
require "net/http"
require "uri"
require "yaml"

module BFP
  module FireRestrictions
    class BoundaryRefresher
      CONFIG_PATH = File.join(BFP.root, "config/fire_restriction_sources.yml")
      OUTPUT_PATH = File.join(BFP.root, "data/fire_restriction_boundaries.geojson")
      SOURCE_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_ForestSystemBoundaries_01/MapServer/0/query"
      SOURCE_LAYER_URL = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_ForestSystemBoundaries_01/MapServer/0"

      BOUNDARY_NAME_BY_SLUG = {
        "klamath" => "Klamath National Forest",
        "ochoco-crooked-river" => "Ochoco National Forest",
        "rogue-river-siskiyou" => "Rogue River-Siskiyou National Forests"
      }.freeze

      def initialize(config_path: CONFIG_PATH, output_path: OUTPUT_PATH)
        @config_path = config_path
        @output_path = output_path
      end

      def refresh
        desired_units = active_land_units.to_h { |unit| [boundary_name_for(unit), unit] }
        source_features = fetch_source_features
        matched_boundary_names = []

        features = source_features.filter_map do |feature|
          boundary_name = feature.dig("properties", "forestname").to_s
          unit = desired_units[boundary_name]
          next unless unit

          matched_boundary_names << boundary_name
          curated_feature(feature, unit, boundary_name)
        end.sort_by { |feature| feature.dig("properties", "slug") }

        missing = desired_units.keys - matched_boundary_names
        raise "Missing USFS boundaries for: #{missing.join(", ")}" unless missing.empty?

        FileUtils.mkdir_p(File.dirname(@output_path))
        File.write(@output_path, "#{JSON.generate(feature_collection(features))}\n")

        features.length
      end

      private

      def active_land_units
        YAML
          .load_file(@config_path)
          .fetch("land_units")
          .select { |unit| unit.fetch("active", true) }
      end

      def boundary_name_for(unit)
        BOUNDARY_NAME_BY_SLUG.fetch(unit.fetch("slug"), unit.fetch("name"))
      end

      def fetch_source_features
        response = Net::HTTP.get_response(source_uri)
        raise "USFS boundary request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data.fetch("features")
      end

      def source_uri
        uri = URI(SOURCE_URL)
        uri.query = URI.encode_www_form(
          "f" => "geojson",
          "where" => "region IN ('05','06')",
          "outFields" => "forestname,region,forestnumber,gis_acres",
          "outSR" => "4326",
          "returnGeometry" => "true",
          "geometryPrecision" => "4",
          "resultRecordCount" => "100"
        )
        uri
      end

      def curated_feature(feature, unit, boundary_name)
        {
          "type" => "Feature",
          "geometry" => feature.fetch("geometry"),
          "properties" => {
            "slug" => unit.fetch("slug"),
            "name" => unit.fetch("name"),
            "boundary_name" => boundary_name,
            "region" => feature.dig("properties", "region"),
            "forest_number" => feature.dig("properties", "forestnumber"),
            "gis_acres" => feature.dig("properties", "gis_acres"),
            "source_url" => SOURCE_LAYER_URL
          }
        }
      end

      def feature_collection(features)
        {
          "type" => "FeatureCollection",
          "name" => "BFP fire restriction forest boundaries",
          "source" => SOURCE_LAYER_URL,
          "features" => features
        }
      end
    end
  end
end
