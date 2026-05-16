Sequel.migration do
  up do
    alter_table(:restriction_observations) do
      add_column :scope, String, default: "forestwide"
    end

    self[:restriction_observations].where(scope: nil).update(scope: "forestwide")

    alter_table(:restriction_observations) do
      set_column_not_null :scope
      add_index [:land_unit_id, :scope, :created_at], name: :restriction_observations_land_scope_created_idx
    end

    create_table(:restriction_areas) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      String :slug, null: false
      String :name, null: false
      String :area_type, null: false
      String :area_description, text: true
      column :geometry_json, :jsonb
      String :geometry_source_type
      String :geometry_source_url
      String :geometry_external_id
      DateTime :geometry_acquired_at
      column :geometry_provenance_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      TrueClass :active, null: false, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:land_unit_id, :slug], unique: true, name: :restriction_areas_land_slug_uidx
      index [:land_unit_id, :active]
      index [:land_unit_id, :area_type]
      index :geometry_external_id
    end

    create_table(:localized_fire_use_rules) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      foreign_key :restriction_area_id, :restriction_areas, on_delete: :set_null
      foreign_key :restriction_observation_id, :restriction_observations, on_delete: :set_null
      foreign_key :restriction_source_id, :restriction_sources, on_delete: :set_null
      foreign_key :source_fetch_id, :source_fetches, on_delete: :set_null
      String :slug, null: false
      String :title, null: false
      String :origin, null: false, default: "parsed_source"
      String :status, null: false, default: "unknown"
      String :campfire_policy, null: false, default: "unknown"
      String :charcoal_policy, null: false, default: "unknown"
      String :gas_stove_policy, null: false, default: "unknown"
      String :liquid_fuel_stove_policy, null: false, default: "unknown"
      String :alcohol_stove_policy, null: false, default: "unknown"
      String :solid_fuel_stove_policy, null: false, default: "unknown"
      String :wood_stove_policy, null: false, default: "unknown"
      TrueClass :stove_shutoff_valve_required
      column :stove_requirements_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      String :duration_type, null: false, default: "unknown"
      Date :effective_start
      Date :effective_end
      Integer :season_start_month
      Integer :season_start_day
      Integer :season_end_month
      Integer :season_end_day
      String :incident_name
      String :incident_number
      String :incident_url
      Date :incident_started_on
      String :affected_area, text: true
      column :geometry_json, :jsonb
      String :geometry_source_type
      String :summary, text: true
      column :evidence_quotes, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      String :source_url
      String :source_title
      Float :confidence, null: false, default: 0.0
      String :review_status, null: false, default: "needs_review"
      DateTime :last_reviewed_at
      Date :next_review_due_on
      String :review_notes, text: true
      DateTime :published_at
      DateTime :superseded_at
      String :content_fingerprint
      foreign_key :supersedes_rule_id, :localized_fire_use_rules, on_delete: :set_null
      column :raw_output, :jsonb
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:land_unit_id, :slug], unique: true, name: :localized_fire_use_rules_land_slug_uidx
      index [:land_unit_id, :review_status, :published_at], name: :localized_fire_use_rules_land_review_published_idx
      index [:land_unit_id, :status]
      index [:land_unit_id, :campfire_policy], name: :localized_fire_use_rules_land_campfire_idx
      index [:restriction_area_id, :published_at], name: :localized_fire_use_rules_area_published_idx
      index :restriction_observation_id, name: :localized_fire_use_rules_observation_idx
      index [:restriction_source_id, :created_at], name: :localized_fire_use_rules_source_created_idx
      index :source_fetch_id
      index :content_fingerprint
      index :next_review_due_on
      index :published_at
      index :superseded_at
      index :supersedes_rule_id
    end

    run <<~SQL
      ALTER TABLE localized_fire_use_rules
        ADD CONSTRAINT localized_fire_use_rules_valid_season_months
        CHECK (
          (season_start_month IS NULL OR season_start_month BETWEEN 1 AND 12)
          AND (season_end_month IS NULL OR season_end_month BETWEEN 1 AND 12)
        )
    SQL

    run <<~SQL
      ALTER TABLE localized_fire_use_rules
        ADD CONSTRAINT localized_fire_use_rules_valid_season_days
        CHECK (
          (season_start_day IS NULL OR season_start_day BETWEEN 1 AND 31)
          AND (season_end_day IS NULL OR season_end_day BETWEEN 1 AND 31)
        )
    SQL
  end

  down do
    drop_table(:localized_fire_use_rules)
    drop_table(:restriction_areas)

    alter_table(:restriction_observations) do
      drop_index [:land_unit_id, :scope, :created_at], name: :restriction_observations_land_scope_created_idx
      drop_column :scope
    end
  end
end
