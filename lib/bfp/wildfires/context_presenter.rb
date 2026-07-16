require "json"
require_relative "proximity"
require_relative "../places/geometry"

module BFP
  module Wildfires
    # Single home for wildfire display policy: staleness TTL, tier -> status
    # rollup, incident list shaping, and GeoJSON map features. Past the TTL it
    # suppresses everything so the site never asserts a stale "active fire" or a
    # false "no fires" claim.
    class ContextPresenter
      DEFAULT_MAX_AGE_HOURS = 6
      MAX_INCIDENTS = 5
      DATA_ATTRIBUTION = "NIFC/WFIGS".freeze
      BOUNDARY_PATH = File.join(BFP.root, "data/fire_restriction_boundaries.geojson")

      def initialize(now: Time.now, boundary_path: BOUNDARY_PATH)
        @now = now
        @boundary_path = boundary_path
      end

      def for_point(latitude:, longitude:)
        return stale_context unless fresh?

        matches = Proximity.classify(longitude: longitude.to_f, latitude: latitude.to_f, incidents: active_incidents)
        context_for(matches)
      end

      def for_land_unit(slug)
        return stale_context unless fresh?

        geometry = boundary_geometry(slug)
        return none_context unless geometry

        matches = Proximity.for_geometry(geometry, incidents: active_incidents)
        context_for(matches)
      end

      def map_features(latitude:, longitude:)
        return [] unless fresh?

        stamp = as_of
        Proximity.distances(longitude: longitude.to_f, latitude: latitude.to_f, incidents: active_incidents)
          .map { |entry| map_feature(entry[:incident], stamp) }
      end

      def map_features_for_land_unit(slug)
        return [] unless fresh?

        geometry = boundary_geometry(slug)
        return [] unless geometry

        stamp = as_of
        Proximity.for_geometry(geometry, incidents: active_incidents)
          .map { |entry| map_feature(entry[:incident], stamp) }
      end

      private

      def context_for(matches)
        {
          status: status_for(matches),
          as_of: as_of,
          incidents: matches.first(MAX_INCIDENTS).map { |match| serialize_incident(match) }
        }
      end

      def status_for(matches)
        return :none if matches.empty?

        matches
          .map { |match| match[:tier] }
          .max_by { |tier| Proximity::TIER_SEVERITY.fetch(tier, 0) }
      end

      def serialize_incident(match)
        incident = match[:incident]
        {
          name: incident.name,
          distance_miles: match[:distance_miles].to_f.round(1),
          acres: incident.acres,
          percent_contained: incident.percent_contained,
          discovered_at: iso8601(incident.discovered_at),
          behavior: incident.behavior,
          irwin_id: incident.irwin_id
        }
      end

      def map_feature(incident, stamp)
        perimeter = incident.perimeter_geometry
        geometry, kind = if perimeter
          [perimeter, "wildfire"]
        else
          [{"type" => "Point", "coordinates" => [incident.longitude, incident.latitude]}, "wildfire_incident"]
        end

        {
          type: "Feature",
          geometry: geometry,
          properties: {
            kind: kind,
            map_status: "wildfire",
            name: incident.name,
            acres: incident.acres,
            percent_contained: incident.percent_contained,
            discovered_at: iso8601(incident.discovered_at),
            irwin_id: incident.irwin_id,
            as_of: stamp,
            data_attribution: DATA_ATTRIBUTION
          }
        }
      end

      def stale_context
        {status: :stale, as_of: nil, incidents: []}
      end

      def none_context
        {status: :none, as_of: as_of, incidents: []}
      end

      def fresh?
        finished = last_successful_sync&.finished_at
        return false unless finished

        finished >= @now - (max_age_hours * 3600)
      end

      def as_of
        finished = last_successful_sync&.finished_at
        iso8601(finished)
      end

      def max_age_hours
        Float(ENV.fetch("WILDFIRE_MAX_AGE_HOURS", DEFAULT_MAX_AGE_HOURS.to_s))
      rescue ArgumentError, TypeError
        DEFAULT_MAX_AGE_HOURS
      end

      def active_incidents
        @active_incidents ||= WildfireIncident.active_set
      end

      def last_successful_sync
        return @last_successful_sync if defined?(@last_successful_sync)

        @last_successful_sync = WildfireSync.last_successful
      end

      def boundary_geometry(slug)
        feature = boundary_features.find { |candidate| candidate.dig("properties", "slug").to_s == slug.to_s }
        return unless feature

        BFP::Places::Geometry.geojson_geometry(feature["geometry"])
      end

      def boundary_features
        @boundary_features ||= load_boundary_features
      end

      def load_boundary_features
        return [] unless File.file?(@boundary_path)

        JSON.parse(File.read(@boundary_path)).fetch("features", [])
      rescue JSON::ParserError
        []
      end

      def iso8601(value)
        value&.iso8601
      end
    end
  end
end
