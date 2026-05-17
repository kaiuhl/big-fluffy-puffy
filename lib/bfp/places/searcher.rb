require "bfp/places/normalizer"

module BFP
  module Places
    class Searcher
      TYPE_BOOSTS = {
        "localized_restriction_area" => 90,
        "trailhead" => 80,
        "campground" => 74,
        "recreation_site" => 68,
        "trail" => 62,
        "lake" => 58,
        "river" => 52,
        "wilderness" => 50,
        "destination" => 48
      }.freeze

      CATEGORY_TYPE_ALIASES = {
        "campground" => %w[campground],
        "camping" => %w[campground],
        "campsite" => %w[campground],
        "campsites" => %w[campground],
        "developed campground" => %w[campground],
        "developed camping" => %w[campground],
        "destination" => %w[destination],
        "forest" => %w[forest],
        "lake" => %w[lake],
        "recreation site" => %w[recreation_site],
        "river" => %w[river],
        "trail" => %w[trail],
        "trailhead" => %w[trailhead],
        "waterfall" => %w[waterfall],
        "wilderness" => %w[wilderness]
      }.freeze

      STATE_NAMES = {
        "or" => "Oregon",
        "wa" => "Washington",
        "ca" => "California"
      }.freeze

      def search(query, limit: 8)
        normalized_query = Normalizer.normalize(query)
        return [] if normalized_query.empty?

        category_types = category_place_types(normalized_query)
        name_rows = matching_name_rows(normalized_query, category_types)
        grouped = name_rows.group_by(&:place_id)
        places_by_id = Place.where(id: grouped.keys).all.to_h { |place| [place.id, place] }

        grouped.filter_map do |place_id, rows|
          place = places_by_id[place_id]
          next unless place&.active

          best_name = rows.max_by { |row| score_name(row, place, normalized_query) }
          suggestion_for(place, best_name, score_name(best_name, place, normalized_query), normalized_query, category_types)
        end.sort_by { |suggestion| [-suggestion[:score], suggestion[:name]] }.first(limit)
      rescue Sequel::DatabaseError
        []
      end

      private

      def matching_name_rows(normalized_query, category_types)
        tokens = normalized_query.split
        dataset = PlaceName
          .join(:places, id: :place_id)
          .where(Sequel[:places][:active] => true)

        token_filter = candidate_name_phrases(tokens, normalized_query).reduce(nil) do |filter, phrase|
          expression = Sequel.ilike(Sequel[:place_names][:normalized_name], "%#{phrase}%")
          filter ? (filter | expression) : expression
        end

        category_filter = category_types.any? ? Sequel.expr(Sequel[:places][:place_type] => category_types) : nil
        filter = [token_filter, category_filter].compact.reduce { |left, right| left | right }

        return [] unless filter

        dataset
          .where(filter)
          .select_all(:place_names)
          .order(
            Sequel.desc(Sequel[:places][:search_rank]),
            Sequel.desc(Sequel[:place_names][:weight]),
            Sequel[:place_names][:name]
          )
          .limit(360)
          .all
      end

      def candidate_name_phrases(tokens, normalized_query)
        return [normalized_query] if tokens.length < 2

        phrases = [normalized_query]
        max_window = [tokens.length, 3].min
        max_window.downto(2) do |window_size|
          tokens.each_cons(window_size) { |phrase_tokens| phrases << phrase_tokens.join(" ") }
        end
        phrases.uniq
      end

      def suggestion_for(place, name_row, score, normalized_query, category_types)
        land_units = matched_land_units_for(place)
        matched_rule_count = place.place_localized_rule_matches_dataset.count
        {
          slug: place.slug,
          name: place.name,
          place_type: place.place_type,
          subtitle: subtitle_for(place, land_units),
          latitude: place.latitude,
          longitude: place.longitude,
          matched_land_units: land_units.map { |unit| {slug: unit.slug, name: unit.name} },
          matched_rule_count: matched_rule_count,
          url: "/trip-check/#{place.slug}",
          match_name: name_row.name,
          match_type: match_type_for(place, name_row.normalized_name, normalized_query, category_types),
          score: score +
            type_query_score(place, category_types) +
            context_score(land_units, matched_rule_count) +
            context_query_score(normalized_query, name_row.normalized_name, place, land_units)
        }
      end

      def matched_land_units_for(place)
        direct = place.place_land_unit_matches_dataset.eager(:land_unit).all.filter_map(&:land_unit)
        from_rules = place.place_localized_rule_matches_dataset
          .eager(localized_fire_use_rule: :land_unit)
          .all
          .filter_map { |match| match.localized_fire_use_rule&.land_unit }

        (direct + from_rules).uniq(&:id)
      end

      def score_name(name_row, place, normalized_query)
        score = place.search_rank.to_i + name_row.weight.to_i + TYPE_BOOSTS.fetch(place.place_type.to_s, 20)
        normalized_name = name_row.normalized_name.to_s

        score += 1000 if normalized_name == normalized_query
        score += 1000 if normalized_query.include?(normalized_name)
        score += 650 if normalized_name.start_with?(normalized_query)
        score += 420 if normalized_name.include?(normalized_query)
        score += 180 if normalized_query.split.all? { |token| normalized_name.include?(token) }
        score
      end

      def type_query_score(place, category_types)
        category_types.include?(place.place_type.to_s) ? 760 : 0
      end

      def category_place_types(normalized_query)
        CATEGORY_TYPE_ALIASES.fetch(normalized_query, [])
      end

      def match_type_for(place, normalized_name, normalized_query, category_types)
        return match_type(normalized_name, normalized_query) if name_matches_query?(normalized_name, normalized_query)
        return "place_type" if category_types.include?(place.place_type.to_s)

        match_type(normalized_name, normalized_query)
      end

      def match_type(normalized_name, normalized_query)
        return "exact" if normalized_name == normalized_query
        return "prefix" if normalized_name.start_with?(normalized_query)
        return "contains" if normalized_name.include?(normalized_query)
        return "name_with_context" if normalized_query.include?(normalized_name)

        "token"
      end

      def name_matches_query?(normalized_name, normalized_query)
        normalized_name == normalized_query ||
          normalized_name.start_with?(normalized_query) ||
          normalized_name.include?(normalized_query) ||
          normalized_query.include?(normalized_name) ||
          normalized_query.split.all? { |token| normalized_name.include?(token) }
      end

      def subtitle_for(place, land_units)
        metadata = place_metadata(place)
        parts = [labelize(place.place_type)]
        parts << land_units.first.name if land_units.first
        parts << metadata["forest_name"] if land_units.empty?
        parts << STATE_NAMES.fetch(place.state_code.to_s, nil)
        parts << county_label(metadata["county_name"])
        parts << quad_label(metadata["map_name"])
        parts.compact.join(" / ")
      end

      def context_score(land_units, matched_rule_count)
        score = 0
        score += 140 if land_units.any?
        score += 80 if matched_rule_count.positive?
        score
      end

      def context_query_score(normalized_query, normalized_name, place, land_units)
        extra_tokens = normalized_query.split - normalized_name.to_s.split
        return 0 if extra_tokens.empty?

        context = Normalizer.normalize(context_values_for(place, land_units).join(" "))
        matching_tokens = extra_tokens.count { |token| context.include?(token) }
        score = matching_tokens * 120
        score += 280 if matching_tokens == extra_tokens.length
        score -= 220 if matching_tokens.zero?
        score
      end

      def context_values_for(place, land_units)
        metadata = place_metadata(place)
        [
          place.state_code,
          STATE_NAMES.fetch(place.state_code.to_s, nil),
          metadata["county_name"],
          metadata["map_name"],
          metadata["state_name"],
          metadata["source_feature_class"],
          metadata["forest_name"],
          metadata["source_activity"],
          metadata["activity_group"],
          *land_units.flat_map { |unit| [unit.slug, unit.name] }
        ].compact
      end

      def place_metadata(place)
        place.respond_to?(:metadata) ? place.metadata : {}
      end

      def county_label(value)
        return if value.to_s.empty?

        value.to_s.end_with?(" County") ? value.to_s : "#{value} County"
      end

      def quad_label(value)
        return if value.to_s.empty?

        "#{value} quad"
      end

      def labelize(value)
        value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
      end
    end
  end
end
