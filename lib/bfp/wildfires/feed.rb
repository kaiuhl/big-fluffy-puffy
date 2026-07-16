require "json"
require "time"
require "uri"
require_relative "../places/geometry"

module BFP
  module Wildfires
    # Pure feed URL building and GeoJSON normalization for the NIFC/WFIGS
    # interagency wildfire feeds. No HTTP or database access lives here so the
    # parsing is fully fixture-testable.
    module Feed
      # Raised when a feed body is not usable GeoJSON: invalid JSON, an ArcGIS
      # error payload (which arrives with HTTP 200), or a missing features
      # array. Sync treats these as failed runs so bad upstream responses never
      # rewrite the incident set.
      class FeedError < StandardError; end

      module_function

      POINTS_LAYER_URL = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Incident_Locations_Current/FeatureServer/0".freeze
      PERIMETERS_LAYER_URL = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0".freeze

      # Pacific Northwest bounding envelope: west, south, east, north (WGS84).
      PNW_ENVELOPE = [-125.1, 41.5, -116.4, 49.1].freeze

      POINT_OUT_FIELDS = %w[IncidentName PercentContained IncidentSize FireDiscoveryDateTime FireBehaviorGeneral IrwinID].freeze
      PERIMETER_OUT_FIELDS = %w[poly_IncidentName attr_PercentContained poly_GISAcres attr_FireDiscoveryDateTime poly_IRWINID].freeze

      EARTH_RADIUS_METERS = 6_378_137.0
      ACRE_SQUARE_METERS = 4046.86
      DEFAULT_POINT_RADIUS_METERS = 500.0

      def points_query_url
        query_url(POINTS_LAYER_URL, POINT_OUT_FIELDS)
      end

      def perimeters_query_url
        query_url(PERIMETERS_LAYER_URL, PERIMETER_OUT_FIELDS)
      end

      def query_url(layer_url, out_fields)
        uri = URI("#{layer_url.sub(%r{/\z}, "")}/query")
        uri.query = URI.encode_www_form(
          where: "1=1",
          geometry: PNW_ENVELOPE.join(","),
          geometryType: "esriGeometryEnvelope",
          inSR: 4326,
          spatialRel: "esriSpatialRelIntersects",
          outFields: out_fields.join(","),
          returnGeometry: "true",
          outSR: 4326,
          f: "geojson"
        )
        uri.to_s
      end

      # Returns an array of normalized incident hashes with keys matching the
      # wildfire_incidents columns (perimeter/attributes still plain hashes).
      def parse(points_body, perimeters_body)
        perimeters_by_irwin = index_perimeters(feature_list(perimeters_body, label: "perimeters"))

        feature_list(points_body, label: "points").filter_map do |feature|
          incident_hash(feature, perimeters_by_irwin)
        end
      end

      def feature_list(body, label: "wildfire")
        payload = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
        error = payload["error"] || payload[:error]
        raise FeedError, "#{label} feed returned an ArcGIS error: #{error.inspect}" if error

        features = payload["features"] || payload[:features]
        raise FeedError, "#{label} feed response has no features array" unless features.is_a?(Array)

        features
      rescue JSON::ParserError => parse_error
        raise FeedError, "#{label} feed returned invalid JSON: #{parse_error.message}"
      end

      def index_perimeters(features)
        features.each_with_object({}) do |feature, by_irwin|
          properties = feature["properties"] || {}
          irwin = normalize_irwin(properties["poly_IRWINID"])
          next unless irwin

          by_irwin[irwin] ||= feature
        end
      end

      def incident_hash(feature, perimeters_by_irwin)
        properties = feature["properties"] || {}
        irwin = normalize_irwin(properties["IrwinID"])
        return unless irwin

        coordinate = point_coordinate(feature["geometry"])
        return unless coordinate

        longitude = coordinate[0].to_f
        latitude = coordinate[1].to_f
        perimeter = perimeters_by_irwin[irwin]
        perimeter_properties = perimeter ? (perimeter["properties"] || {}) : {}
        perimeter_geometry = perimeter && perimeter["geometry"]

        acres = numeric(perimeter_properties["poly_GISAcres"]) || numeric(properties["IncidentSize"])
        percent_contained = numeric(perimeter_properties["attr_PercentContained"]) || numeric(properties["PercentContained"])
        discovered_at = epoch_ms_to_time(properties["FireDiscoveryDateTime"]) ||
          epoch_ms_to_time(perimeter_properties["attr_FireDiscoveryDateTime"])

        {
          irwin_id: irwin,
          name: (properties["IncidentName"] || perimeter_properties["poly_IncidentName"]).to_s.strip,
          acres: acres,
          percent_contained: percent_contained,
          discovered_at: discovered_at,
          behavior: properties["FireBehaviorGeneral"],
          latitude: latitude,
          longitude: longitude,
          perimeter_geometry_json: perimeter_geometry,
          attributes_json: {
            "point" => properties,
            "perimeter" => (perimeter_properties unless perimeter_properties.empty?)
          }.compact,
          **bounds_for(perimeter_geometry, longitude, latitude, acres)
        }
      end

      def bounds_for(perimeter_geometry, longitude, latitude, acres)
        bounds = BFP::Places::Geometry.bounds_for_geojson(perimeter_geometry) if perimeter_geometry
        bounds ||= point_bounds(longitude, latitude, acres)
        {
          min_lon: bounds[0],
          min_lat: bounds[1],
          max_lon: bounds[2],
          max_lat: bounds[3]
        }
      end

      def point_bounds(longitude, latitude, acres)
        radius = point_radius_meters(acres)
        latitude_radians = latitude * Math::PI / 180.0
        delta_lat = radius / EARTH_RADIUS_METERS * 180.0 / Math::PI
        delta_lon = radius / (EARTH_RADIUS_METERS * Math.cos(latitude_radians)) * 180.0 / Math::PI
        [longitude - delta_lon, latitude - delta_lat, longitude + delta_lon, latitude + delta_lat]
      end

      def point_radius_meters(acres)
        value = acres.to_f
        return DEFAULT_POINT_RADIUS_METERS if value <= 0

        [Math.sqrt(value * ACRE_SQUARE_METERS / Math::PI), DEFAULT_POINT_RADIUS_METERS].max
      end

      def point_coordinate(geometry)
        return unless geometry.is_a?(Hash)

        coordinates = geometry["coordinates"]
        case geometry["type"]
        when "Point"
          coordinates if coordinates.is_a?(Array) && coordinates.length >= 2
        when "MultiPoint"
          coordinates&.first if coordinates.is_a?(Array)
        end
      end

      def normalize_irwin(value)
        normalized = value.to_s.gsub(/[{}]/, "").strip.upcase
        normalized.empty? ? nil : normalized
      end

      def epoch_ms_to_time(value)
        return if value.nil?
        return value if value.is_a?(Time)

        milliseconds = Float(value)
        Time.at(milliseconds / 1000.0).utc
      rescue ArgumentError, TypeError
        nil
      end

      def numeric(value)
        return if value.nil? || value == ""

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
