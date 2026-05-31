require "date"

module BFP
  module FireRestrictions
    class LocalizedRuleValidator
      STATUS_VALUES = %w[unknown advisory partial stage_1 stage_2 full closure year_round].freeze
      CAMPFIRE_POLICY_VALUES = %w[unknown allowed developed_sites_only fire_pan_required prohibited propane_allowed stoves_only].freeze
      STOVE_POLICY_VALUES = %w[unknown allowed fire_pan_required prohibited developed_sites_only allowed_with_shutoff_valve].freeze
      DURATION_TYPE_VALUES = %w[unknown permanent seasonal temporary incident].freeze
      AREA_TYPE_VALUES = %w[
        unknown
        ranger_district
        wilderness
        corridor
        campground
        trail
        trailhead
        watershed
        incident_area
        administrative_area
        named_area
        map_area
        other
      ].freeze
      GEOMETRY_SOURCE_TYPE_VALUES = %w[
        unknown
        none
        text_description
        source_map
        source_pdf_map
        source_arcgis_feature
        geojson
        linked_map
        usfs_edw_wilderness
        usgs_nhd_waterbody
        derived_nhd_centroid_buffer
        derived_nhd_waterbody_buffer
        derived_nhd_flowline_buffer
        derived_gnis_feature_buffer
        affected_area_envelope
        derived_dem_elevation
        derived_usfs_trail_boundary_polygon
        official_order_map_pending
        named_area_manual_review
      ].freeze
      RESTRICTIVE_STATUSES = %w[advisory partial stage_1 stage_2 full closure year_round].freeze
      RESTRICTIVE_EVIDENCE = ObservationValidator::RESTRICTIVE_EVIDENCE

      Result = Struct.new(:valid?, :errors, keyword_init: true)

      def initialize(today: Date.today)
        @today = today
      end

      def validate(rule, source:, extracted_text:)
        errors = []
        text = extracted_text.to_s

        validate_presence(rule, errors)
        validate_enum("status", rule["status"], STATUS_VALUES, errors)
        validate_enum("campfire_policy", rule["campfire_policy"], CAMPFIRE_POLICY_VALUES, errors)
        %w[
          charcoal_policy
          gas_stove_policy
          liquid_fuel_stove_policy
          alcohol_stove_policy
          solid_fuel_stove_policy
          wood_stove_policy
        ].each { |field| validate_enum(field, rule[field], STOVE_POLICY_VALUES, errors) }
        validate_enum("duration_type", rule["duration_type"], DURATION_TYPE_VALUES, errors)
        validate_enum("area_type", rule["area_type"], AREA_TYPE_VALUES, errors)
        validate_enum("geometry_source_type", rule["geometry_source_type"], GEOMETRY_SOURCE_TYPE_VALUES, errors)
        validate_dates(rule, errors)
        validate_season(rule, errors)
        validate_evidence(rule, source, text, errors)
        validate_geometry(rule, errors)

        Result.new(valid?: errors.empty?, errors: errors)
      end

      def strong?(rule, validation)
        validation.valid? &&
          rule["confidence"].to_f >= 0.9 &&
          Array(rule["needs_review_reasons"]).empty? &&
          RESTRICTIVE_STATUSES.include?(rule["status"].to_s)
      end

      private

      def validate_presence(rule, errors)
        errors << "Localized rule title is missing." if rule["title"].to_s.strip.empty?
        errors << "Localized rule affected area is missing." if rule["affected_area"].to_s.strip.empty?
        errors << "Localized rule evidence is missing." if Array(rule["evidence_quotes"]).empty?
      end

      def validate_enum(field, value, allowed, errors)
        return if allowed.include?(value.to_s)

        errors << "Localized rule #{field} is unsupported: #{value.inspect}"
      end

      def validate_dates(rule, errors)
        effective_start = parse_date(rule["effective_start"])
        effective_end = parse_date(rule["effective_end"])

        if rule["effective_start"] && !effective_start
          errors << "Localized rule effective_start is not a valid date."
        end

        if rule["effective_end"] && !effective_end
          errors << "Localized rule effective_end is not a valid date."
        elsif effective_end && effective_end < @today && RESTRICTIVE_STATUSES.include?(rule["status"].to_s) && !recurring_seasonal_rule?(rule)
          errors << "Localized rule effective_end is in the past."
        end

        if effective_start && effective_end && effective_start > effective_end
          errors << "Localized rule effective_start is after effective_end."
        end
      end

      def validate_season(rule, errors)
        {
          "season_start_month" => 1..12,
          "season_end_month" => 1..12,
          "season_start_day" => 1..31,
          "season_end_day" => 1..31
        }.each do |field, range|
          value = rule[field]
          next if value.nil?
          next if value.is_a?(Integer) && range.cover?(value)

          errors << "Localized rule #{field} is outside #{range.first}-#{range.last}."
        end
      end

      def recurring_seasonal_rule?(rule)
        return false unless rule["duration_type"].to_s == "seasonal"

        {
          "season_start_month" => 1..12,
          "season_end_month" => 1..12,
          "season_start_day" => 1..31,
          "season_end_day" => 1..31
        }.all? do |field, range|
          value = integer_value(rule[field])
          value && range.cover?(value)
        end
      end

      def validate_evidence(rule, source, text, errors)
        evidence_quotes = Array(rule["evidence_quotes"]).compact.map(&:to_s)

        unless source.source_type == "arcgis_feature_layer"
          evidence_quotes.each do |quote|
            next if quote.strip.empty?
            next if includes_normalized?(text, quote)

            errors << "Localized rule evidence quote does not match extracted text: #{quote[0, 120]}"
          end
        end

        if RESTRICTIVE_STATUSES.include?(rule["status"].to_s)
          evidence_text = evidence_quotes.join("\n")
          evidence_text = text if evidence_text.strip.empty?
          errors << "Localized rule restrictive status lacks restriction/prohibition evidence." unless evidence_text.match?(RESTRICTIVE_EVIDENCE)
        end
      end

      def validate_geometry(rule, errors)
        geometry = rule["geometry_json"]
        return if geometry.nil?
        return if explicit_geojson?(geometry)

        errors << "Localized rule geometry_json is not explicit GeoJSON geometry."
      end

      def explicit_geojson?(value)
        return false unless value.is_a?(Hash)

        %w[Point MultiPoint LineString MultiLineString Polygon MultiPolygon GeometryCollection Feature FeatureCollection].include?(value["type"].to_s)
      end

      def parse_date(value)
        return if value.to_s.strip.empty?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def integer_value(value)
        return if value.nil? || value.to_s.strip.empty?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def includes_normalized?(haystack, needle)
        normalize(haystack).include?(normalize(needle))
      end

      def normalize(value)
        value.to_s.tr("\u00a0\u202f", "  ").gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
