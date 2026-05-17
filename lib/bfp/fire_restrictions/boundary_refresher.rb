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
      NPS_SOURCE_URL = "https://services1.arcgis.com/fBc8EJBxQRMcHlei/ArcGIS/rest/services/NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/FeatureServer/2/query"
      NPS_SOURCE_LAYER_URL = "https://services1.arcgis.com/fBc8EJBxQRMcHlei/ArcGIS/rest/services/NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/FeatureServer/2"

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
        features = (usfs_boundary_features + nps_boundary_features)
          .sort_by { |feature| feature.dig("properties", "slug") }

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

      def usfs_land_units
        active_land_units.reject { |unit| unit.fetch("agency", "USFS") == "NPS" }
      end

      def nps_land_units
        active_land_units.select { |unit| unit.fetch("agency", "USFS") == "NPS" }
      end

      def usfs_boundary_features
        desired_units = usfs_land_units.to_h { |unit| [boundary_name_for(unit), unit] }
        return [] if desired_units.empty?

        source_features = fetch_usfs_source_features
        matched_boundary_names = []

        features = source_features.filter_map do |feature|
          boundary_name = feature.dig("properties", "forestname").to_s
          unit = desired_units[boundary_name]
          next unless unit

          matched_boundary_names << boundary_name
          curated_usfs_feature(feature, unit, boundary_name)
        end

        missing = desired_units.keys - matched_boundary_names
        raise "Missing USFS boundaries for: #{missing.join(", ")}" unless missing.empty?

        features
      end

      def nps_boundary_features
        units = nps_land_units
        return [] if units.empty?

        codes = units.flat_map { |unit| nps_boundary_codes(unit) }.uniq
        source_features = fetch_nps_source_features(codes)
        features_by_code = source_features.group_by { |feature| feature.dig("properties", "UNIT_CODE").to_s }

        units.map do |unit|
          unit_codes = nps_boundary_codes(unit)
          matched_features = unit_codes.flat_map { |code| features_by_code.fetch(code, []) }
          missing_codes = unit_codes - matched_features.map { |feature| feature.dig("properties", "UNIT_CODE").to_s }.uniq
          raise "Missing NPS boundaries for #{unit.fetch("slug")}: #{missing_codes.join(", ")}" unless missing_codes.empty?

          curated_nps_feature(matched_features, unit, unit_codes)
        end
      end

      def boundary_name_for(unit)
        BOUNDARY_NAME_BY_SLUG.fetch(unit.fetch("slug"), unit.fetch("name"))
      end

      def nps_boundary_codes(unit)
        Array(unit["boundary_source_codes"]).map(&:to_s).reject(&:empty?)
      end

      def fetch_usfs_source_features
        response = Net::HTTP.get_response(usfs_source_uri)
        raise "USFS boundary request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data.fetch("features")
      end

      def fetch_nps_source_features(codes)
        response = Net::HTTP.get_response(nps_source_uri(codes))
        raise "NPS boundary request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data.fetch("features")
      end

      def usfs_source_uri
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

      def nps_source_uri(codes)
        uri = URI(NPS_SOURCE_URL)
        uri.query = URI.encode_www_form(
          "f" => "geojson",
          "where" => "UNIT_CODE IN (#{codes.map { |code| "'#{code}'" }.join(",")})",
          "outFields" => "UNIT_CODE,UNIT_NAME,PARKNAME,UNIT_TYPE,STATE,REGION,Shape__Area",
          "outSR" => "4326",
          "returnGeometry" => "true",
          "geometryPrecision" => "4",
          "resultRecordCount" => "100"
        )
        uri
      end

      def curated_usfs_feature(feature, unit, boundary_name)
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

      def curated_nps_feature(features, unit, unit_codes)
        properties = features.map { |feature| feature.fetch("properties", {}) }

        {
          "type" => "Feature",
          "geometry" => combined_geometry(features),
          "properties" => {
            "slug" => unit.fetch("slug"),
            "name" => unit.fetch("name"),
            "boundary_name" => unit.fetch("name"),
            "region" => unit["region_code"],
            "agency" => "NPS",
            "nps_unit_codes" => unit_codes,
            "nps_unit_names" => properties.map { |property| property["UNIT_NAME"] }.compact.uniq,
            "nps_unit_types" => properties.map { |property| property["UNIT_TYPE"] }.compact.uniq,
            "state" => properties.map { |property| property["STATE"] }.compact.uniq.join(","),
            "source_url" => NPS_SOURCE_LAYER_URL
          }
        }
      end

      def combined_geometry(features)
        polygons = features.flat_map do |feature|
          geometry = feature.fetch("geometry")
          case geometry.fetch("type")
          when "Polygon"
            [geometry.fetch("coordinates")]
          when "MultiPolygon"
            geometry.fetch("coordinates")
          else
            []
          end
        end

        {
          "type" => "MultiPolygon",
          "coordinates" => polygons
        }
      end

      def feature_collection(features)
        {
          "type" => "FeatureCollection",
          "name" => "BFP fire restriction land unit boundaries",
          "source" => [SOURCE_LAYER_URL, NPS_SOURCE_LAYER_URL],
          "features" => features
        }
      end
    end
  end
end
