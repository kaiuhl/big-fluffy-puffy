require "json"
require_relative "status_display"

module BFP
  module FireRestrictions
    class MapPresenter
      BOUNDARY_PATH = File.join(BFP.root, "data/fire_restriction_boundaries.geojson")

      def initialize(records:, boundary_path: BOUNDARY_PATH)
        @records = records
        @boundary_path = boundary_path
      end

      def geojson
        records_by_slug = @records.to_h { |record| [record.fetch(:slug).to_s, record] }

        features = boundary_features.filter_map do |feature|
          slug = feature.dig("properties", "slug").to_s
          record = records_by_slug[slug]
          next unless record

          map_feature(feature, record)
        end

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

      def map_feature(feature, record)
        source = preferred_source(record)

        checked_at = checked_at_for(record, source)

        {
          type: "Feature",
          geometry: feature.fetch("geometry"),
          properties: {
            slug: record[:slug],
            name: record[:name],
            forest_url: record[:forest_url] || "/fire-restrictions/#{record[:slug]}",
            region_code: record[:region_code],
            status: record[:status],
            campfire_policy: StatusDisplay.campfire_policy(
              status: record[:status],
              campfire_policy: record[:campfire_policy]
            ),
            review_status: record[:review_status],
            last_checked_at: checked_at,
            last_checked_label: checked_at ? StatusDisplay.checked_date_label(checked_at) : "not checked",
            source_url: record[:source_url] || source&.fetch(:url, nil),
            source_title: record[:source_title] || source&.fetch(:name, nil),
            climate_low_context: record[:climate_low_context],
            map_status: map_status(record)
          }
        }
      end

      def map_status(record)
        return "none" if published_status?(record) && record[:status].to_s == "none"
        return "active" if published_status?(record) && record[:status].to_s != "unknown"

        "unknown"
      end

      def published_status?(record)
        %w[accepted auto_accepted].include?(record[:review_status].to_s)
      end

      def preferred_source(record)
        return {url: record[:source_url], name: record[:source_title], last_checked_at: record[:last_checked_at]} if record[:source_url]

        Array(record[:sources]).min_by { |source| [source_rank(source), source[:name].to_s] }
      end

      def source_rank(source)
        {
          "fs_fire_info_page" => 0,
          "fs_fire_page" => 1,
          "fs_alerts_page" => 2,
          "fs_release_page" => 3
        }.fetch(source[:source_type].to_s, 9)
      end

      def checked_at_for(record, source)
        record[:last_checked_at] || source&.fetch(:last_checked_at, nil)
      end
    end
  end
end
