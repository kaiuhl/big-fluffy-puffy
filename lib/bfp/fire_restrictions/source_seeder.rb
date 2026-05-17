require "yaml"

module BFP
  module FireRestrictions
    class SourceSeeder
      CONFIG_PATH = File.join(BFP.root, "config/fire_restriction_sources.yml")

      def initialize(path: CONFIG_PATH)
        @path = path
      end

      def seed
        config = YAML.load_file(@path)
        defaults = config.fetch("defaults", {})
        source_paths = defaults.fetch("source_paths", [])
        default_poll_interval = defaults.fetch("poll_interval_minutes", 720)
        counts = {land_units: 0, sources: 0}

        BFP.db.transaction do
          config.fetch("land_units").each do |unit_config|
            land_unit = upsert_land_unit(unit_config)
            counts[:land_units] += 1

            generated_source_paths(unit_config, source_paths).each do |source_path|
              upsert_source(land_unit, source_from_path(unit_config, source_path, default_poll_interval))
              counts[:sources] += 1
            end

            unit_config.fetch("sources", []).each do |source_config|
              upsert_source(land_unit, source_config.merge("poll_interval_minutes" => source_config.fetch("poll_interval_minutes", default_poll_interval)))
              counts[:sources] += 1
            end
          end
        end

        counts
      end

      private

      def upsert_land_unit(config)
        now = Time.now
        land_unit = LandUnit.first(slug: config.fetch("slug")) || LandUnit.new(slug: config.fetch("slug"), created_at: now)
        land_unit.set(
          name: config.fetch("name"),
          unit_type: config.fetch("unit_type"),
          agency: config.fetch("agency", "USFS"),
          region_code: config["region_code"],
          forest_slug: config["forest_slug"],
          market_bucket: config.fetch("market_bucket", "core_pnw"),
          official_url: config["official_url"],
          boundary_source_url: config["boundary_source_url"],
          geometry_json: Jsonb.wrap(config["geometry_json"]),
          active: config.fetch("active", true),
          updated_at: now
        )
        land_unit.save
        land_unit
      end

      def upsert_source(land_unit, config)
        now = Time.now
        source = RestrictionSource.first(slug: config.fetch("slug")) ||
          RestrictionSource.new(slug: config.fetch("slug"), created_at: now)

        source.set(
          land_unit_id: land_unit.id,
          name: config.fetch("name"),
          source_type: config.fetch("source_type"),
          authority: config.fetch("authority", "official_usfs"),
          url: config.fetch("url"),
          parser_key: config.fetch("parser_key", "usfs_html"),
          poll_interval_minutes: config.fetch("poll_interval_minutes", 720),
          active: config.fetch("active", land_unit.active),
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: now
        )
        source.save
        source
      end

      def generated_source_paths(unit_config, default_source_paths)
        base_paths = unit_config.key?("source_paths") ? unit_config.fetch("source_paths") : default_source_paths
        base_paths + unit_config.fetch("extra_source_paths", [])
      end

      def source_from_path(unit_config, source_path, default_poll_interval)
        {
          "slug" => "#{unit_config.fetch("slug")}-#{source_path.fetch("key")}",
          "name" => source_path.fetch("name"),
          "source_type" => source_path.fetch("source_type"),
          "authority" => source_path.fetch("authority", "official_usfs"),
          "url" => "#{unit_config.fetch("official_url").sub(%r{/\z}, "")}#{source_path.fetch("path")}",
          "parser_key" => source_path.fetch("parser_key", "usfs_html"),
          "poll_interval_minutes" => source_path.fetch("poll_interval_minutes", default_poll_interval),
          "active" => unit_config.fetch("active", true),
          "metadata_json" => source_path["metadata_json"] || {}
        }
      end
    end
  end
end
