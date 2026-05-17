require "json"
require_relative "forest_status_presenter"
require_relative "map_presenter"

module BFP
  module FireRestrictions
    class ForestMapPresenter
      BOUNDARY_PATH = MapPresenter::BOUNDARY_PATH

      def initialize(slug:, boundary_path: BOUNDARY_PATH, forest_presenter: ForestStatusPresenter.new)
        @slug = slug
        @boundary_path = boundary_path
        @forest_presenter = forest_presenter
      end

      def geojson
        detail = @forest_presenter.forest(@slug)
        return unless detail

        forest = detail.fetch(:forest)
        features = []
        boundary = boundary_feature(forest.fetch(:slug))
        features << map_boundary_feature(boundary, forest) if boundary
        features.concat(localized_features(detail.fetch(:localized_restrictions)))

        {
          type: "FeatureCollection",
          features: features
        }
      end

      private

      def boundary_features
        return [] unless File.file?(@boundary_path)

        JSON.parse(File.read(@boundary_path)).fetch("features", [])
      rescue JSON::ParserError
        []
      end

      def boundary_feature(slug)
        boundary_features.find { |feature| feature.dig("properties", "slug").to_s == slug.to_s }
      end

      def map_boundary_feature(feature, forest)
        {
          type: "Feature",
          geometry: feature.fetch("geometry"),
          properties: {
            kind: "forest_boundary",
            slug: forest[:slug],
            name: forest[:name],
            forest_url: forest[:forest_url],
            status: forest[:status],
            campfire_policy: forest[:campfire_policy],
            review_status: forest[:review_status],
            map_status: "boundary",
            source_url: forest[:source_url],
            source_title: forest[:source_title]
          }
        }
      end

      def localized_features(rules)
        rules.flat_map do |rule|
          geometry = rule[:geometry_json]
          next [] unless geojson_geometry?(geometry)

          subfeatures = localized_subfeatures(rule, geometry)
          next subfeatures if subfeatures.any?

          [localized_feature(geometry, localized_properties(rule))]
        end
      end

      def localized_subfeatures(rule, geometry)
        coordinates = geometry_coordinates(geometry)
        return [] unless geometry_type(geometry) == "MultiPolygon" && coordinates.is_a?(Array)

        map_subfeatures(rule).filter_map do |subfeature|
          indexes = Array(hash_fetch(subfeature, "geometry_part_indexes")).filter_map do |index|
            Integer(index)
          rescue ArgumentError, TypeError
            nil
          end
          parts = indexes.filter_map { |index| coordinates[index] }
          next if parts.empty?

          properties = localized_properties(rule).merge(
            map_feature_role: "restriction_part",
            part_name: hash_fetch(subfeature, "part_name"),
            restriction_detail: hash_fetch(subfeature, "restriction_detail"),
            geometry_basis: hash_fetch(subfeature, "geometry_basis"),
            source_kind: hash_fetch(subfeature, "source_kind")
          ).compact

          localized_feature(
            {
              "type" => "MultiPolygon",
              "coordinates" => parts
            },
            properties
          )
        end
      end

      def localized_feature(geometry, properties)
        {
          type: "Feature",
          geometry: geometry,
          properties: properties
        }
      end

      def localized_properties(rule)
        {
          kind: "localized_restriction",
          id: rule[:id],
          slug: rule[:slug],
          rule_slug: rule[:slug],
          name: rule[:title],
          status: rule[:status],
          duration_type: rule[:duration_type],
          campfire_policy: rule[:campfire_policy],
          gas_stove_policy: rule[:gas_stove_policy],
          alcohol_stove_policy: rule[:alcohol_stove_policy],
          solid_fuel_stove_policy: rule[:solid_fuel_stove_policy],
          wood_stove_policy: rule[:wood_stove_policy],
          map_status: "active",
          affected_area: rule[:affected_area],
          geometry_source_type: rule[:geometry_source_type],
          geometry_accuracy: rule.dig(:geometry_provenance, "geometry_accuracy") || rule.dig(:geometry_provenance, :geometry_accuracy),
          geometry_is_approximate: approximate_geometry?(rule),
          source_url: rule[:source_url],
          source_title: rule[:source_title]
        }
      end

      def geojson_geometry?(geometry)
        geometry = geometry.to_hash if geometry.respond_to?(:to_hash)
        !!(geometry.is_a?(Hash) && geometry_type(geometry).to_s != "" && geometry_coordinates(geometry))
      end

      def geometry_type(geometry)
        hash_fetch(geometry, "type")
      end

      def geometry_coordinates(geometry)
        hash_fetch(geometry, "coordinates")
      end

      def map_subfeatures(rule)
        Array(rule.dig(:geometry_provenance, "map_subfeatures") || rule.dig(:geometry_provenance, :map_subfeatures)).select { |item| item.is_a?(Hash) }
      end

      def hash_fetch(hash, key)
        return unless hash.is_a?(Hash)
        return hash[key] if hash.key?(key)

        hash[key.to_sym]
      end

      def approximate_geometry?(rule)
        source_type = rule[:geometry_source_type].to_s
        accuracy = rule.dig(:geometry_provenance, "geometry_accuracy") || rule.dig(:geometry_provenance, :geometry_accuracy)

        accuracy.to_s == "approximate" || source_type.start_with?("derived_")
      end
    end
  end
end
