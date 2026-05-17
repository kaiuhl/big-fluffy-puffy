require "yaml"

module BFP
  module Places
    class ManualSeeder
      CONFIG_PATH = File.join(BFP.root, "config/place_manual.yml")

      def initialize(path: CONFIG_PATH, now: Time.now)
        @path = path
        @now = now
      end

      def seed
        counts = {datasets: 0, places: 0, names: 0, localized_areas: 0}

        BFP.db.transaction do
          dataset = upsert_dataset(manual_dataset_config)
          counts[:datasets] += 1
          manual_place_ids = []

          Array(manual_config.fetch("places", [])).each do |config|
            place = upsert_place(dataset, config)
            manual_place_ids << place.id
            counts[:places] += 1
            counts[:names] += upsert_names(place, names_for(config)).length
          end
          deactivate_stale_places(dataset, manual_place_ids)

          localized_dataset = upsert_dataset(localized_dataset_config)
          counts[:datasets] += 1
          localized_place_ids = []
          localized_area_configs.each do |config|
            place = upsert_place(localized_dataset, config)
            localized_place_ids << place.id
            counts[:localized_areas] += 1
            counts[:names] += upsert_names(place, names_for(config)).length
          end
          deactivate_stale_places(localized_dataset, localized_place_ids)
        end

        counts
      end

      private

      def manual_config
        @manual_config ||= File.file?(@path) ? YAML.load_file(@path) : {"places" => []}
      end

      def manual_dataset_config
        manual_config.fetch("dataset", {}).merge(
          "slug" => "bfp-manual",
          "name" => manual_config.dig("dataset", "name") || "BFP curated destinations",
          "license_name" => manual_config.dig("dataset", "license_name") || "BFP curated",
          "attribution_text" => manual_config.dig("dataset", "attribution_text") || "Curated by Big Fluffy Puffy."
        )
      end

      def localized_dataset_config
        {
          "slug" => "bfp-localized-restriction-areas",
          "name" => "BFP localized fire-use restriction areas",
          "source_url" => "/fire-restrictions",
          "license_name" => "BFP curated",
          "attribution_text" => "Derived from BFP-reviewed official fire-use restriction sources."
        }
      end

      def upsert_dataset(config)
        dataset = PlaceDataset.first(slug: config.fetch("slug")) || PlaceDataset.new(slug: config.fetch("slug"), created_at: @now)
        dataset.set(
          name: config.fetch("name"),
          source_url: config["source_url"],
          license_name: config.fetch("license_name"),
          license_url: config["license_url"],
          attribution_text: config["attribution_text"],
          retrieved_at: @now,
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: @now
        )
        dataset.save
        dataset
      end

      def upsert_place(dataset, config)
        slug = config["slug"].to_s.strip
        slug = "#{dataset.slug}-#{Normalizer.slugify(config.fetch("name"))}" if slug.empty?
        place = Place.first(slug: slug) || Place.new(slug: slug, created_at: @now)
        geometry = config["geometry_json"]
        center = Geometry.center_for(geometry)
        place.set(
          name: config.fetch("name"),
          place_type: config.fetch("place_type", "destination"),
          latitude: config["latitude"] || center&.first,
          longitude: config["longitude"] || center&.last,
          geometry_json: Jsonb.wrap(geometry),
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          state_code: config["state_code"],
          source_dataset_id: dataset.id,
          source_external_id: config["source_external_id"],
          source_url: config["source_url"] || dataset.source_url,
          confidence: config.fetch("confidence", 0.9),
          search_rank: config.fetch("search_rank", 80),
          active: config.fetch("active", true),
          updated_at: @now
        )
        place.save
        place
      end

      def localized_area_configs
        published_rules.filter_map do |rule|
          area = rule.restriction_area
          geometry = json_hash(rule.geometry_json || area&.geometry_json)
          next unless area && geometry

          center = Geometry.center_for(geometry)
          {
            "slug" => "localized-#{area.slug}",
            "name" => area.name,
            "place_type" => "localized_restriction_area",
            "latitude" => center&.first,
            "longitude" => center&.last,
            "geometry_json" => geometry,
            "source_external_id" => area.slug,
            "source_url" => rule.source_url || rule.restriction_source&.url,
            "confidence" => 0.95,
            "search_rank" => 95,
            "aliases" => [rule.title, rule.affected_area].compact,
            "state_code" => state_code_for(rule.land_unit)
          }
        end
      end

      def published_rules
        BFP::FireRestrictions::LocalizedFireUseRule
          .where(review_status: %w[accepted auto_accepted], superseded_at: nil)
          .all
      end

      def upsert_names(place, names)
        names.uniq.filter_map do |name|
          normalized = Normalizer.normalize(name)
          next if normalized.empty?

          record = PlaceName.first(place_id: place.id, normalized_name: normalized) ||
            PlaceName.new(place_id: place.id, normalized_name: normalized, created_at: @now)
          record.set(
            name: name,
            kind: (name == place.name) ? "official" : "alias",
            weight: (name == place.name) ? 100 : 75,
            updated_at: @now
          )
          record.save
        end
      end

      def deactivate_stale_places(dataset, active_ids)
        stale = Place.where(source_dataset_id: dataset.id)
        stale = stale.exclude(id: active_ids) unless active_ids.empty?
        stale.update(active: false, updated_at: @now)
      end

      def names_for(config)
        [config.fetch("name"), *Array(config["aliases"])].compact.map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def json_hash(value)
        return if value.nil?
        return value.to_hash if value.respond_to?(:to_hash)

        value
      end

      def state_code_for(land_unit)
        market_bucket = land_unit.market_bucket.to_s
        return "ca" if market_bucket.include?("california") || market_bucket.include?("tahoe")
        return "wa" if market_bucket.include?("washington")
        return "or" if market_bucket.include?("oregon")

        nil
      end
    end
  end
end
