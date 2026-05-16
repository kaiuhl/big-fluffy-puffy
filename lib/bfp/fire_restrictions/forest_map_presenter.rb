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
        rules.filter_map do |rule|
          geometry = rule[:geometry_json]
          next unless geojson_geometry?(geometry)

          {
            type: "Feature",
            geometry: geometry,
            properties: {
              kind: "localized_restriction",
              id: rule[:id],
              slug: rule[:slug],
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
              source_url: rule[:source_url],
              source_title: rule[:source_title]
            }
          }
        end
      end

      def geojson_geometry?(geometry)
        geometry.is_a?(Hash) &&
          (geometry["type"] || geometry[:type]).to_s != "" &&
          (geometry["coordinates"] || geometry[:coordinates])
      end
    end
  end
end
