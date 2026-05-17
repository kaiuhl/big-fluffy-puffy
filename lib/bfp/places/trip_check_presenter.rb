require "date"
require "bfp/fire_restrictions/forest_status_presenter"
require "bfp/fire_restrictions/status_display"

module BFP
  module Places
    class TripCheckPresenter
      POLICY_PRIORITY = {
        "prohibited" => 5,
        "developed_sites_only" => 4,
        "fire_pan_required" => 3,
        "allowed_with_shutoff_valve" => 2,
        "allowed" => 1,
        "unknown" => 0
      }.freeze

      FIRE_USE_KEYS = %i[
        campfire_policy
        gas_stove_policy
        liquid_fuel_stove_policy
        alcohol_stove_policy
        charcoal_policy
        solid_fuel_stove_policy
        wood_stove_policy
      ].freeze

      def initialize(on: Date.today, forest_presenter: BFP::FireRestrictions::ForestStatusPresenter.new(on: on))
        @on = on
        @forest_presenter = forest_presenter
      end

      def check(slug)
        place = Place.first(slug: slug.to_s, active: true)
        return unless place

        land_unit_matches = place.place_land_unit_matches_dataset.eager(:land_unit).all
        matched_rule_records = matched_localized_rule_records(place)
        forest_details = forest_details_for(land_unit_matches, matched_rule_records)
        active_rules = active_localized_rules(matched_rule_records, forest_details)
        fire_use = combined_fire_use(forest_details, active_rules)
        campfire_policy = fire_use.fetch(:campfire_policy, "unknown")

        {
          place: serialize_place(place),
          verdict: verdict_for(campfire_policy, forest_details, active_rules),
          campfire_policy: campfire_policy,
          fire_use: fire_use,
          matched_land_units: serialize_land_unit_matches(land_unit_matches, forest_details),
          localized_restrictions: active_rules,
          datasets: serialize_datasets(place),
          official_sources: official_sources(forest_details, active_rules),
          confidence: confidence_for(place, land_unit_matches, active_rules),
          checked_at: checked_at_for(forest_details),
          map: map_payload(place, active_rules)
        }
      rescue Sequel::DatabaseError
        nil
      end

      def map(slug)
        check = check(slug)
        return unless check

        {
          type: "FeatureCollection",
          features: map_features(check)
        }
      end

      private

      def map_features(check)
        features = []
        place = check.fetch(:place)
        features << place_feature(place) if place[:latitude] && place[:longitude]
        features.concat(localized_rule_features(check.fetch(:localized_restrictions)))
        features
      end

      def place_feature(place)
        {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [place.fetch(:longitude), place.fetch(:latitude)]
          },
          properties: {
            kind: "trip_check_place",
            name: place.fetch(:name),
            status: "destination",
            campfire_policy: "unknown",
            map_status: "unknown",
            source_url: place[:source_url],
            source_title: "Place source",
            last_checked_label: "place match"
          }
        }
      end

      def localized_rule_features(rules)
        rules.filter_map do |rule|
          geometry = rule[:geometry_json]
          next unless geometry

          {
            type: "Feature",
            geometry: geometry,
            properties: {
              kind: "localized_restriction",
              id: rule[:id],
              slug: rule[:slug],
              rule_slug: rule[:slug],
              name: rule[:title],
              status: rule[:status],
              campfire_policy: rule[:campfire_policy],
              map_status: "active",
              affected_area: rule[:affected_area],
              geometry_source_type: rule[:geometry_source_type],
              geometry_is_approximate: approximate_geometry?(rule),
              source_url: rule[:source_url],
              source_title: rule[:source_title]
            }
          }
        end
      end

      def approximate_geometry?(rule)
        source_type = rule[:geometry_source_type].to_s
        accuracy = rule.dig(:geometry_provenance, "geometry_accuracy") || rule.dig(:geometry_provenance, :geometry_accuracy)

        accuracy.to_s == "approximate" || source_type.start_with?("derived_")
      end

      def forest_detail_for(land_unit)
        return unless land_unit

        @forest_presenter.forest(land_unit.slug)
      end

      def matched_localized_rule_records(place)
        place.place_localized_rule_matches_dataset
          .eager(localized_fire_use_rule: :land_unit)
          .all
          .filter_map(&:localized_fire_use_rule)
      end

      def forest_details_for(land_unit_matches, rule_records)
        land_units = land_unit_matches.filter_map(&:land_unit) + rule_records.filter_map(&:land_unit)
        land_units.uniq(&:id).filter_map { |land_unit| forest_detail_for(land_unit) }
      end

      def active_localized_rules(rule_records, forest_details)
        matched_ids = rule_records.map(&:id)
        return [] if matched_ids.empty?

        forest_details
          .flat_map { |detail| detail.fetch(:localized_restrictions, []) }
          .select { |rule| matched_ids.include?(rule[:id]) }
      end

      def combined_fire_use(forest_details, rules)
        values = FIRE_USE_KEYS.to_h { |key| [key, "unknown"] }
        forest_policies = forest_details.map { |detail| detail.dig(:forest, :campfire_policy) }
        values[:campfire_policy] = strongest_policy(forest_policies)

        rules.each do |rule|
          FIRE_USE_KEYS.each do |key|
            values[key] = strongest_policy([values[key], rule[key]])
          end
        end

        values
      end

      def strongest_policy(values)
        values
          .map { |value| value.to_s.empty? ? "unknown" : value.to_s }
          .max_by { |value| POLICY_PRIORITY.fetch(value, 0) } || "unknown"
      end

      def verdict_for(campfire_policy, forest_details, rules)
        if forest_details.empty?
          {
            tone: "unknown",
            headline: "Outside BFP's monitored fire-restriction area.",
            detail: "BFP does not yet have a forest match for this place. Check the managing agency before you go."
          }
        elsif rules.any? && campfire_policy == "prohibited"
          {
            tone: "active",
            headline: "Campfires appear prohibited here.",
            detail: "A matched localized fire-use rule applies to this destination. Use the official source and posted signs for exact boundaries."
          }
        elsif campfire_policy == "prohibited"
          {
            tone: "active",
            headline: "Campfires appear prohibited in the matched forest.",
            detail: "BFP found a published forest-wide restriction for this destination."
          }
        elsif %w[developed_sites_only fire_pan_required allowed_with_shutoff_valve].include?(campfire_policy)
          {
            tone: "limited",
            headline: "Campfires appear limited here.",
            detail: "There are conditions attached to fire use. Read the matched source before relying on a fire."
          }
        elsif campfire_policy == "allowed"
          {
            tone: "clear",
            headline: "No BFP-published campfire prohibition is matched here.",
            detail: "This is not official permission. Confirm current agency sources and signs before you go."
          }
        else
          {
            tone: "unknown",
            headline: "BFP does not have a confident fire-use answer here yet.",
            detail: "Unknown does not mean campfires are allowed."
          }
        end
      end

      def serialize_place(place)
        {
          slug: place.slug,
          name: place.name,
          place_type: place.place_type,
          latitude: place.latitude,
          longitude: place.longitude,
          state_code: place.state_code,
          source_url: place.source_url
        }
      end

      def serialize_land_unit_matches(matches, forest_details)
        details_by_slug = forest_details.to_h { |detail| [detail.dig(:forest, :slug), detail.fetch(:forest)] }
        serialized = matches.filter_map do |match|
          land_unit = match.land_unit
          forest = details_by_slug[land_unit&.slug]
          next unless land_unit && forest

          {
            relationship: match.relationship,
            confidence: match.confidence.to_f,
            forest: forest
          }
        end

        existing_slugs = serialized.map { |match| match.dig(:forest, :slug) }
        serialized.concat(details_by_slug.filter_map do |slug, forest|
          next if existing_slugs.include?(slug)

          {
            relationship: "localized_rule_context",
            confidence: 0.86,
            forest: forest
          }
        end)

        serialized
      end

      def serialize_datasets(place)
        [place.source_dataset].compact.map do |dataset|
          {
            name: dataset.name,
            license_name: dataset.license_name,
            license_url: dataset.license_url,
            attribution_text: dataset.attribution_text,
            source_url: dataset.source_url
          }
        end
      end

      def official_sources(forest_details, rules)
        sources = forest_details.filter_map do |detail|
          forest = detail.fetch(:forest)
          next unless forest[:source_url]

          {title: forest[:source_title] || forest[:name], url: forest[:source_url], checked_at: forest[:last_checked_at]}
        end

        sources.concat(rules.filter_map do |rule|
          next unless rule[:source_url]

          {title: rule[:source_title] || rule[:title], url: rule[:source_url], checked_at: rule[:last_checked_at]}
        end)

        sources.uniq { |source| source[:url] }
      end

      def confidence_for(place, matches, rules)
        values = [place.confidence.to_f]
        values.concat(matches.map { |match| match.confidence.to_f })
        values.concat(rules.map { |rule| rule[:confidence].to_f })
        values.compact.min || 0.0
      end

      def checked_at_for(forest_details)
        forest_details.filter_map { |detail| detail.dig(:forest, :last_checked_at) }.max
      end

      def map_payload(place, rules)
        center = if [place.latitude, place.longitude].compact.length == 2
          [place.latitude, place.longitude]
        end

        {
          center: center,
          localized_rule_count: rules.count { |rule| rule[:mapped] }
        }
      end
    end
  end
end
