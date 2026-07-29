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

      # National InciWeb incident feed. Only larger, staffed incidents get an
      # InciWeb page, so this is a best-effort enrichment: it supplies an
      # authoritative per-fire information link and is joined by protecting unit
      # plus incident name. Fetched non-fatally by Sync.
      INCIWEB_RSS_URL = "https://inciweb.wildfire.gov/incidents/rss.xml".freeze

      # Pacific Northwest bounding envelope: west, south, east, north (WGS84).
      PNW_ENVELOPE = [-125.1, 41.5, -116.4, 49.1].freeze

      POINT_OUT_FIELDS = %w[IncidentName PercentContained IncidentSize FireDiscoveryDateTime FireBehaviorGeneral IrwinID POOProtectingUnit IncidentTypeCategory IncidentShortDescription TotalIncidentPersonnel].freeze
      PERIMETER_OUT_FIELDS = %w[poly_IncidentName attr_PercentContained poly_GISAcres attr_FireDiscoveryDateTime poly_IRWINID].freeze

      # Both feeds are paged with a stable sort so a growing incident set can
      # never silently truncate (or blow the fetcher's body cap) the way an
      # unbounded single request does.
      PAGE_SIZE = 250
      POINT_ORDER_FIELD = "IrwinID".freeze
      PERIMETER_ORDER_FIELD = "poly_IRWINID".freeze

      # Full-fidelity PNW perimeters passed 12 MB in July 2026 and failed every
      # sync for days. Generalizing rings to ~55 m at 5 decimal places is about
      # twenty times smaller and still far finer than the 10/30-mile proximity
      # tiers or map rendering need.
      PERIMETER_GEOMETRY_PRECISION = 5
      PERIMETER_MAX_ALLOWABLE_OFFSET = 0.0005

      # ArcGIS reports throttling and transient server trouble as an error
      # payload under HTTP 200; these codes are worth retrying, others are not.
      RETRYABLE_ERROR_CODES = [429, 500, 502, 503, 504].freeze

      EARTH_RADIUS_METERS = 6_378_137.0
      ACRE_SQUARE_METERS = 4046.86
      DEFAULT_POINT_RADIUS_METERS = 500.0

      def points_query_url(offset: 0)
        query_url(POINTS_LAYER_URL, POINT_OUT_FIELDS, order_by: POINT_ORDER_FIELD, offset: offset)
      end

      def perimeters_query_url(offset: 0)
        query_url(
          PERIMETERS_LAYER_URL,
          PERIMETER_OUT_FIELDS,
          order_by: PERIMETER_ORDER_FIELD,
          offset: offset,
          extra: {
            geometryPrecision: PERIMETER_GEOMETRY_PRECISION,
            maxAllowableOffset: PERIMETER_MAX_ALLOWABLE_OFFSET
          }
        )
      end

      def query_url(layer_url, out_fields, order_by: nil, offset: 0, extra: {})
        uri = URI("#{layer_url.sub(%r{/\z}, "")}/query")
        uri.query = URI.encode_www_form(
          {
            where: "1=1",
            geometry: PNW_ENVELOPE.join(","),
            geometryType: "esriGeometryEnvelope",
            inSR: 4326,
            spatialRel: "esriSpatialRelIntersects",
            outFields: out_fields.join(","),
            returnGeometry: "true",
            outSR: 4326,
            orderByFields: order_by,
            resultOffset: offset,
            resultRecordCount: PAGE_SIZE,
            f: "geojson"
          }.merge(extra).compact
        )
        uri.to_s
      end

      # True when ArcGIS cut the page short at the layer's max record count, so
      # the caller should request the next resultOffset.
      def more_pages?(body)
        payload = payload_for(body)
        return false unless payload

        value = payload.dig("properties", "exceededTransferLimit")
        value = payload["exceededTransferLimit"] if value.nil?
        value == true || value.to_s == "true"
      end

      # The ArcGIS error code when the reply is one worth retrying (throttling
      # or a transient server error), otherwise nil.
      def retryable_error_code(body)
        payload = payload_for(body)
        return unless payload

        code = payload.dig("error", "code")
        code if RETRYABLE_ERROR_CODES.include?(code)
      end

      # Returns an array of normalized incident hashes with keys matching the
      # wildfire_incidents columns (perimeter/attributes still plain hashes).
      # Each feed argument is either a single response body or an already
      # validated feature array (Sync pages the feeds and validates per page).
      # inciweb_entries is the already-parsed output of parse_inciweb; parse
      # stays pure and never does HTTP, so callers fetch the RSS themselves.
      def parse(points, perimeters, inciweb_entries: [])
        perimeters_by_irwin = index_perimeters(features_for(perimeters, label: "perimeters"))

        features_for(points, label: "points").filter_map do |feature|
          incident_hash(feature, perimeters_by_irwin, inciweb_entries)
        end
      end

      def features_for(value, label:)
        value.is_a?(Array) ? value : feature_list(value, label: label)
      end

      # Parses the InciWeb incidents RSS into normalized join entries. Each item
      # title is "<UNITID> <Fire Name>"; the first whitespace token is the
      # protecting unit and the remainder is the incident name (with a trailing
      # "Fire" stripped) so it lines up with WFIGS IncidentName. Raises FeedError
      # on nil/empty/unrecognizable bodies, matching the rest of the feed's
      # strictness; Sync rescues that so a bad RSS reply never fails a sync.
      def parse_inciweb(body)
        raise FeedError, "InciWeb RSS feed body was empty" if body.nil?

        text = body.to_s.dup.force_encoding("UTF-8")
        raise FeedError, "InciWeb RSS feed body was empty" if text.strip.empty?
        unless text.include?("<item") || text.include?("<rss") || text.include?("<channel")
          raise FeedError, "InciWeb RSS feed body was not recognizable RSS"
        end

        text.scan(%r{<item\b[^>]*>(.*?)</item>}mi).filter_map do |(item)|
          title = decode_entities(extract_tag(item, "title"))
          link = decode_entities(extract_tag(item, "link"))
          next if title.nil? || link.nil?

          unit, name = split_inciweb_title(title)
          next if unit.nil? || name.nil?

          # The RSS still emits http:// links; InciWeb 301s them to https.
          {unit: unit, name: name, url: link.sub(%r{\Ahttp://(?=inciweb\.wildfire\.gov/)}, "https://")}
        end
      end

      # Best-effort authoritative link for a WFIGS point: prefer an exact match
      # on protecting unit and normalized name, then fall back to a name-only
      # match but only when exactly one RSS entry carries that name.
      def information_url_for(properties, entries)
        return if entries.nil? || entries.empty?

        name = normalize_incident_name(properties["IncidentName"])
        return if name.nil?

        unit = normalize_unit(properties["POOProtectingUnit"])
        if unit
          exact = entries.find { |entry| entry[:unit] == unit && entry[:name] == name }
          return exact[:url] if exact
        end

        name_matches = entries.select { |entry| entry[:name] == name }
        (name_matches.length == 1) ? name_matches.first[:url] : nil
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

      def payload_for(body)
        payload = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
        payload.is_a?(Hash) ? payload : nil
      rescue JSON::ParserError
        nil
      end

      def index_perimeters(features)
        features.each_with_object({}) do |feature, by_irwin|
          properties = feature["properties"] || {}
          irwin = normalize_irwin(properties["poly_IRWINID"])
          next unless irwin

          by_irwin[irwin] ||= feature
        end
      end

      def incident_hash(feature, perimeters_by_irwin, inciweb_entries = [])
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
          information_url: information_url_for(properties, inciweb_entries),
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

      def split_inciweb_title(title)
        parts = title.to_s.strip.split(/\s+/, 2)
        return [nil, nil] if parts.length < 2

        [normalize_unit(parts[0]), normalize_incident_name(parts[1])]
      end

      def normalize_unit(value)
        normalized = value.to_s.strip.upcase
        normalized.empty? ? nil : normalized
      end

      def normalize_incident_name(value)
        normalized = value.to_s.strip.sub(/\s*fire\z/i, "").strip.downcase
        normalized.empty? ? nil : normalized
      end

      def extract_tag(fragment, tag)
        raw = fragment[%r{<#{tag}\b[^>]*>(.*?)</#{tag}>}mi, 1]
        return if raw.nil?

        raw = raw[/\A\s*<!\[CDATA\[(.*?)\]\]>\s*\z/m, 1] || raw
        stripped = raw.strip
        stripped.empty? ? nil : stripped
      end

      def decode_entities(value)
        return if value.nil?

        value
          .gsub("&lt;", "<")
          .gsub("&gt;", ">")
          .gsub("&quot;", "\"")
          .gsub("&#39;", "'")
          .gsub("&apos;", "'")
          .gsub("&amp;", "&")
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
