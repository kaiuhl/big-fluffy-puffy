require "json"
require "uri"

module BFP
  module FireRestrictions
    class ArcgisAdapter
      STATUS_MAP = {
        0 => ["none", "allowed", "No restrictions"],
        1 => ["partial", "developed_sites_only", "Partial restrictions"],
        2 => ["full", "prohibited", "Full restrictions"]
      }.freeze

      STATUS_FIELDS = %w[Status FireRestrictionStatus RestrictionStatus restriction_status status].freeze
      DATA_SOURCE_FIELDS = %w[DataSource data_source Source source].freeze

      def self.query_url(layer_url)
        uri = URI("#{layer_url.sub(%r{/\z}, "")}/query")
        uri.query = URI.encode_www_form(
          where: "1=1",
          outFields: "*",
          returnGeometry: "true",
          f: "json"
        )
        uri.to_s
      end

      def parse(text:, source:, land_unit:)
        payload = JSON.parse(text.to_s)
        feature = matching_feature(payload.fetch("features", []), source.metadata["data_source"])
        return unknown("No matching ArcGIS feature found for #{land_unit.name}.") unless feature

        attributes = feature.fetch("attributes", {})
        raw_status = status_value(attributes)
        status, campfire_policy, label = mapped_status(raw_status)
        feature_text = JSON.generate(feature)

        {
          "status" => status,
          "campfire_policy" => campfire_policy,
          "fire_danger_rating" => nil,
          "ifpl_level" => nil,
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => attributes.fetch("Comments", nil),
          "summary" => arcgis_summary(label, attributes),
          "evidence_quotes" => [feature_text],
          "confidence" => (status == "unknown") ? 0.35 : 0.95,
          "needs_review_reasons" => (status == "unknown") ? ["Unexpected ArcGIS restriction status: #{raw_status.inspect}"] : [],
          "parser_provider" => "deterministic",
          "parser_model_id" => "central_oregon_arcgis",
          "geometry_json" => feature["geometry"]
        }
      rescue JSON::ParserError => error
        unknown("ArcGIS JSON parse failed: #{error.message}")
      end

      private

      def matching_feature(features, data_source)
        return features.first unless data_source

        features.find do |feature|
          attributes = feature.fetch("attributes", {})
          data_source_value = DATA_SOURCE_FIELDS.filter_map { |field| attributes[field] }.first.to_s
          data_source_value.casecmp?(data_source) || data_source_value.include?(data_source)
        end
      end

      def status_value(attributes)
        raw = STATUS_FIELDS.filter_map { |field| attributes[field] }.first
        (raw.is_a?(String) && raw.match?(/\A\d+\z/)) ? raw.to_i : raw
      end

      def mapped_status(raw_status)
        STATUS_MAP.fetch(raw_status, ["unknown", "unknown", "Unknown restrictions"])
      end

      def arcgis_summary(label, attributes)
        comments = attributes["Comments"].to_s.strip
        comments.empty? ? label : "#{label}. #{comments}"
      end

      def unknown(reason)
        {
          "status" => "unknown",
          "campfire_policy" => "unknown",
          "fire_danger_rating" => nil,
          "ifpl_level" => nil,
          "effective_start" => nil,
          "effective_end" => nil,
          "order_number" => nil,
          "affected_area" => nil,
          "summary" => nil,
          "evidence_quotes" => [],
          "confidence" => 0.0,
          "needs_review_reasons" => [reason],
          "parser_provider" => "deterministic",
          "parser_model_id" => "central_oregon_arcgis"
        }
      end
    end
  end
end
