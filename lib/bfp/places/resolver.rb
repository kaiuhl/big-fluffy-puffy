require "json"

module BFP
  module Places
    class Resolver
      BOUNDARY_PATH = File.join(BFP.root, "data/fire_restriction_boundaries.geojson")

      def initialize(boundary_path: BOUNDARY_PATH, now: Time.now)
        @boundary_path = boundary_path
        @now = now
      end

      def resolve(dataset_slug: nil)
        counts = {land_unit_matches: 0, localized_rule_matches: 0}
        scoped_places = places(dataset_slug: dataset_slug)

        BFP.db.transaction do
          reset_matches(scoped_places, scoped: !dataset_slug.to_s.empty?)
          land_unit_match_rows = []
          localized_rule_match_rows = []

          scoped_places.each do |place|
            place_geometry = place_geometry_for(place)
            point = Geometry.point_for(place)
            place_bounds = Geometry.bounds_for_place(place)

            boundary_geometries.each do |land_unit, geometry, bounds|
              next unless Geometry.bounds_intersect?(place_bounds, bounds)

              relationship = land_unit_relationship(place_geometry, point, geometry)
              next unless relationship

              land_unit_match_rows << land_unit_match_row(place, land_unit, relationship)
            end

            localized_rule_geometries.each do |rule, geometry, bounds|
              next unless Geometry.bounds_intersect?(place_bounds, bounds)

              relationship = localized_rule_relationship(place_geometry, point, geometry)
              next unless relationship

              localized_rule_match_rows << localized_rule_match_row(place, rule, relationship)
            end
          end

          insert_match_rows(PlaceLandUnitMatch, land_unit_match_rows)
          insert_match_rows(PlaceLocalizedRuleMatch, localized_rule_match_rows)
          counts[:land_unit_matches] = land_unit_match_rows.length
          counts[:localized_rule_matches] = localized_rule_match_rows.length
        end

        counts
      end

      private

      def places(dataset_slug: nil)
        dataset = PlaceDataset.first(slug: dataset_slug) unless dataset_slug.to_s.empty?
        return [] if dataset_slug.to_s != "" && !dataset

        scope = Place.where(active: true)
        scope = scope.where(source_dataset_id: dataset.id) if dataset
        scope.all
      end

      def reset_matches(scoped_places, scoped:)
        unless scoped
          PlaceLandUnitMatch.dataset.delete
          PlaceLocalizedRuleMatch.dataset.delete
          return
        end

        place_ids = scoped_places.map(&:id)
        return if place_ids.empty?

        PlaceLandUnitMatch.where(place_id: place_ids).delete
        PlaceLocalizedRuleMatch.where(place_id: place_ids).delete
      end

      def boundary_geometries
        @boundary_geometries ||= begin
          features = File.file?(@boundary_path) ? JSON.parse(File.read(@boundary_path)).fetch("features", []) : []
          land_units_by_slug = BFP::FireRestrictions::LandUnit.where(active: true).all.to_h { |unit| [unit.slug, unit] }

          features.filter_map do |feature|
            land_unit = land_units_by_slug[feature.dig("properties", "slug").to_s]
            geometry = Geometry.geojson_geometry(feature["geometry"])
            bounds = Geometry.bounds_for_geojson(feature["geometry"])
            [land_unit, geometry, bounds] if land_unit && geometry
          end
        end
      end

      def localized_rule_geometries
        @localized_rule_geometries ||= BFP::FireRestrictions::LocalizedFireUseRule
          .where(review_status: %w[accepted auto_accepted], superseded_at: nil)
          .all
          .filter_map do |rule|
            geometry_json = json_hash(rule.geometry_json || rule.restriction_area&.geometry_json)
            geometry = Geometry.geojson_geometry(geometry_json)
            bounds = Geometry.bounds_for_geojson(geometry_json)
            [rule, geometry, bounds] if geometry
          end
      end

      def place_geometry_for(place)
        Geometry.geojson_geometry(place.geometry)
      end

      def land_unit_relationship(place_geometry, point, boundary_geometry)
        return "contains_point" if point && Geometry.contains_point?(boundary_geometry, point)
        return "intersects_geometry" if place_geometry && Geometry.intersects?(place_geometry, boundary_geometry)

        nil
      end

      def localized_rule_relationship(place_geometry, point, rule_geometry)
        return "contains_point" if point && Geometry.contains_point?(rule_geometry, point)
        return "intersects_geometry" if place_geometry && Geometry.intersects?(place_geometry, rule_geometry)

        nil
      end

      def land_unit_match_row(place, land_unit, relationship)
        {
          place_id: place.id,
          land_unit_id: land_unit.id,
          relationship: relationship,
          match_method: "rgeo_cached_v1",
          confidence: (relationship == "contains_point") ? 0.98 : 0.86,
          created_at: @now,
          updated_at: @now
        }
      end

      def localized_rule_match_row(place, rule, relationship)
        {
          place_id: place.id,
          localized_fire_use_rule_id: rule.id,
          relationship: relationship,
          match_method: "rgeo_cached_v1",
          confidence: (relationship == "contains_point") ? 0.98 : 0.84,
          distance_meters: 0,
          created_at: @now,
          updated_at: @now
        }
      end

      def insert_match_rows(model, rows)
        rows.each_slice(1000) { |batch| model.multi_insert(batch) }
      end

      def json_hash(value)
        return if value.nil?
        return value.to_hash if value.respond_to?(:to_hash)

        value
      end
    end
  end
end
