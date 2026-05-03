Sequel.migration do
  up do
    create_table(:climate_datasets) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :provider, null: false
      String :variable, null: false
      Integer :normal_period_start_year, null: false
      Integer :normal_period_end_year, null: false
      Integer :spatial_resolution_m
      String :source_url
      String :citation, text: true
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :slug
      index :variable
    end

    create_table(:land_unit_climate_normals) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      foreign_key :climate_dataset_id, :climate_datasets, null: false, on_delete: :cascade
      Integer :month, null: false
      Integer :elevation_min_ft, null: false
      Integer :elevation_max_ft
      String :elevation_band_label, null: false
      BigDecimal :mean_low_f, null: false, size: [6, 2]
      BigDecimal :cold_p10_low_f, size: [6, 2]
      BigDecimal :warm_p90_low_f, size: [6, 2]
      Integer :sample_cell_count, null: false
      BigDecimal :area_acres, size: [12, 2]
      BigDecimal :area_pct_of_forest, size: [7, 3]
      column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :land_unit_id
      index :climate_dataset_id
      index [:land_unit_id, :month]
    end

    run <<~SQL
      CREATE UNIQUE INDEX land_unit_climate_normals_unique_band
        ON land_unit_climate_normals (
          land_unit_id,
          climate_dataset_id,
          month,
          elevation_min_ft,
          elevation_max_ft
        )
        NULLS NOT DISTINCT
    SQL

    run <<~SQL
      ALTER TABLE land_unit_climate_normals
        ADD CONSTRAINT land_unit_climate_normals_valid_month
        CHECK (month BETWEEN 1 AND 12)
    SQL

    run <<~SQL
      ALTER TABLE land_unit_climate_normals
        ADD CONSTRAINT land_unit_climate_normals_positive_sample_count
        CHECK (sample_cell_count > 0)
    SQL

    run <<~SQL
      ALTER TABLE land_unit_climate_normals
        ADD CONSTRAINT land_unit_climate_normals_valid_elevation_range
        CHECK (elevation_max_ft IS NULL OR elevation_max_ft > elevation_min_ft)
    SQL
  end

  down do
    drop_table(:land_unit_climate_normals)
    drop_table(:climate_datasets)
  end
end
