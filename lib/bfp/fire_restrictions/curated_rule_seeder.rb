require "date"
require "digest"
require "json"
require "time"
require "yaml"

module BFP
  module FireRestrictions
    class CuratedRuleSeeder
      CONFIG_PATH = File.join(BFP.root, "config/fire_restriction_curated_rules.yml")
      MUTABLE_REVIEW_KEYS = %w[
        review_status
        review_notes
        published_at
        last_reviewed_at
        next_review_due_on
      ].freeze
      REVIEW_NEUTRAL_TOP_LEVEL_KEYS = (MUTABLE_REVIEW_KEYS + %w[
        seed_review_override
        geometry_json
        geometry_source_type
      ]).freeze
      REVIEW_NEUTRAL_AREA_KEYS = %w[
        slug
        name
        area_type
        area_description
        geometry_path
        geometry_json
        geometry_source_type
        geometry_source_url
        geometry_external_id
        geometry_acquired_at
        geometry_provenance
        geometry_provenance_json
        active
      ].freeze
      PUBLISHABLE_REVIEW_STATUSES = %w[accepted auto_accepted].freeze

      def initialize(path: CONFIG_PATH, now: Time.now)
        @path = path
        @now = now
      end

      def seed
        config = YAML.load_file(@path) || {}
        counts = {areas: 0, rules: 0, changed_rules: 0}

        BFP.db.transaction do
          config.fetch("localized_rules", []).each do |rule_config|
            land_unit = land_unit_for(rule_config)
            area = upsert_area(land_unit, rule_config["area"])
            result = upsert_rule(land_unit, area, rule_config)

            counts[:areas] += 1 if area
            counts[:rules] += 1
            counts[:changed_rules] += 1 if result == :review_changed
          end
        end

        counts
      end

      private

      def land_unit_for(config)
        LandUnit.first(slug: config.fetch("land_unit_slug")) ||
          raise(ArgumentError, "Unknown land unit slug: #{config.fetch("land_unit_slug")}")
      end

      def source_for(config)
        source_slug = config["source_slug"].to_s
        return if source_slug.empty?

        RestrictionSource.first(slug: source_slug) ||
          raise(ArgumentError, "Unknown restriction source slug: #{source_slug}")
      end

      def upsert_area(land_unit, config)
        return unless config

        now = @now
        area = RestrictionArea.first(land_unit_id: land_unit.id, slug: config.fetch("slug")) ||
          RestrictionArea.new(land_unit_id: land_unit.id, slug: config.fetch("slug"), created_at: now)

        area.set(
          name: config.fetch("name"),
          area_type: config.fetch("area_type"),
          area_description: config["area_description"],
          geometry_json: Jsonb.wrap(geometry_json_for(config)),
          geometry_source_type: config["geometry_source_type"],
          geometry_source_url: config["geometry_source_url"],
          geometry_external_id: config["geometry_external_id"],
          geometry_acquired_at: parse_time(config["geometry_acquired_at"]),
          geometry_provenance_json: Jsonb.wrap(config["geometry_provenance_json"] || config["geometry_provenance"] || {}),
          active: config.fetch("active", true),
          updated_at: now
        )
        area.save
        area
      end

      def upsert_rule(land_unit, area, config)
        now = @now
        source = source_for(config)
        fingerprint = fingerprint_for(config)
        existing = LocalizedFireUseRule.first(land_unit_id: land_unit.id, slug: config.fetch("slug"))
        rule = existing || LocalizedFireUseRule.new(land_unit_id: land_unit.id, slug: config.fetch("slug"), created_at: now)
        changed = existing && existing.content_fingerprint.to_s != "" && existing.content_fingerprint != fingerprint
        review_affecting_changed = review_affecting_changed?(existing, config, changed)
        review_required = review_affecting_changed && !seed_review_override?(config)
        review_status = review_status_for(config, existing, changed, review_required)

        rule.set(rule_attributes(config, land_unit, area, source, fingerprint, review_status, review_required, existing, now))
        rule.save

        review_required ? :review_changed : :seeded
      end

      def rule_attributes(config, land_unit, area, source, fingerprint, review_status, review_required, existing, now)
        attributes = {
          land_unit_id: land_unit.id,
          restriction_area_id: area&.id,
          restriction_source_id: source&.id,
          source_fetch_id: nil,
          title: config.fetch("title"),
          origin: config.fetch("origin", "curated"),
          status: config.fetch("status", "unknown"),
          campfire_policy: config.fetch("campfire_policy", "unknown"),
          charcoal_policy: config.fetch("charcoal_policy", "unknown"),
          gas_stove_policy: config.fetch("gas_stove_policy", "unknown"),
          liquid_fuel_stove_policy: config.fetch("liquid_fuel_stove_policy", "unknown"),
          alcohol_stove_policy: config.fetch("alcohol_stove_policy", "unknown"),
          solid_fuel_stove_policy: config.fetch("solid_fuel_stove_policy", "unknown"),
          wood_stove_policy: config.fetch("wood_stove_policy", "unknown"),
          stove_shutoff_valve_required: config["stove_shutoff_valve_required"],
          stove_requirements_json: Jsonb.wrap(config["stove_requirements_json"] || config["stove_requirements"] || {}),
          duration_type: config.fetch("duration_type", "unknown"),
          effective_start: parse_date(config["effective_start"]),
          effective_end: parse_date(config["effective_end"]),
          season_start_month: config["season_start_month"],
          season_start_day: config["season_start_day"],
          season_end_month: config["season_end_month"],
          season_end_day: config["season_end_day"],
          incident_name: config["incident_name"],
          incident_number: config["incident_number"],
          incident_url: config["incident_url"],
          incident_started_on: parse_date(config["incident_started_on"]),
          affected_area: config["affected_area"] || area&.name,
          geometry_json: Jsonb.wrap(geometry_json_for(config)),
          geometry_source_type: config["geometry_source_type"],
          summary: config["summary"],
          evidence_quotes: Jsonb.wrap(Array(config["evidence_quotes"])),
          source_url: config["source_url"] || source&.url,
          source_title: config["source_title"] || source&.name,
          confidence: Float(config.fetch("confidence", 0.0)),
          review_status: review_status,
          next_review_due_on: parse_date(config["next_review_due_on"]),
          review_notes: review_notes_for(config, review_required: review_required),
          published_at: published_at_for(config, review_status, existing),
          content_fingerprint: fingerprint,
          supersedes_rule_id: nil,
          raw_output: Jsonb.wrap(config),
          metadata_json: Jsonb.wrap(config["metadata_json"] || {}),
          updated_at: now
        }

        attributes[:last_reviewed_at] = parse_time(config["last_reviewed_at"]) if config.key?("last_reviewed_at")
        attributes
      end

      def review_status_for(config, existing, changed, review_required)
        return "needs_review" if review_required
        return config.fetch("review_status", "needs_review") if changed && seed_review_override?(config)
        return existing.review_status if existing && existing.review_status.to_s != ""

        config.fetch("review_status", "needs_review")
      end

      def review_notes_for(config, review_required:)
        return "Curated rule content changed during seed; review before publishing." if review_required

        config["review_notes"]
      end

      def published_at_for(config, review_status, existing)
        configured = parse_time(config["published_at"])
        return configured if configured
        return existing.published_at if existing&.published_at && PUBLISHABLE_REVIEW_STATUSES.include?(review_status)
        return @now if PUBLISHABLE_REVIEW_STATUSES.include?(review_status)

        nil
      end

      def fingerprint_for(config)
        stable = config.reject { |key, _value| MUTABLE_REVIEW_KEYS.include?(key.to_s) }
        Digest::SHA256.hexdigest(canonical_json(stable))
      end

      def review_affecting_changed?(existing, config, changed)
        return false unless existing && changed

        review_affecting_fingerprint_for(existing.raw_output || {}) != review_affecting_fingerprint_for(config)
      end

      def review_affecting_fingerprint_for(config)
        stable = review_affecting_config(config)
        Digest::SHA256.hexdigest(canonical_json(stable))
      end

      def review_affecting_config(config)
        stable = config.reject { |key, _value| REVIEW_NEUTRAL_TOP_LEVEL_KEYS.include?(key.to_s) }
        area = hash_fetch(stable, "area")
        metadata = hash_fetch(stable, "metadata_json")

        if area.is_a?(Hash)
          review_area = review_affecting_area(area)
          stable = if review_area.empty?
            stable.reject { |key, _value| key.to_s == "area" }
          else
            stable.merge("area" => review_area)
          end
        end
        stable = stable.merge("metadata_json" => review_affecting_metadata(metadata)) if metadata.is_a?(Hash)
        stable
      end

      def review_affecting_area(area)
        area.reject { |key, _value| REVIEW_NEUTRAL_AREA_KEYS.include?(key.to_s) }
      end

      def review_affecting_metadata(metadata)
        metadata.reject { |key, _value| key.to_s.start_with?("geometry_") }
      end

      def seed_review_override?(config)
        PUBLISHABLE_REVIEW_STATUSES.include?(config["review_status"].to_s) &&
          config["seed_review_override"].to_s != ""
      end

      def geometry_json_for(config)
        return config["geometry_json"] if config.key?("geometry_json")

        geometry_path = config["geometry_path"].to_s
        return if geometry_path.empty?

        payload = JSON.parse(File.read(File.join(BFP.root, geometry_path)))
        if payload["type"] == "FeatureCollection"
          feature = payload.fetch("features").first
          feature&.fetch("geometry")
        elsif payload["type"] == "Feature"
          payload.fetch("geometry")
        else
          payload
        end
      end

      def canonical_json(value)
        case value
        when Hash
          JSON.generate(value.keys.map(&:to_s).sort.to_h { |key| [key, canonical_value(hash_fetch(value, key))] })
        else
          JSON.generate(canonical_value(value))
        end
      end

      def canonical_value(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.to_h { |key| [key, canonical_value(hash_fetch(value, key))] }
        when Array
          value.map { |item| canonical_value(item) }
        when Date, Time
          value.iso8601
        else
          value
        end
      end

      def parse_date(value)
        return if value.to_s.strip.empty?
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def parse_time(value)
        return if value.to_s.strip.empty?
        return value if value.is_a?(Time)

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def hash_fetch(hash, key)
        return hash[key] if hash.key?(key)

        hash[key.to_sym]
      end
    end
  end
end
