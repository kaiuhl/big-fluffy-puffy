Sequel.migration do
  change do
    create_table(:wildfire_incidents) do
      primary_key :id
      String :irwin_id, null: false
      String :name
      Float :acres
      Float :percent_contained
      DateTime :discovered_at
      String :behavior
      Float :latitude
      Float :longitude
      column :perimeter_geometry_json, :jsonb
      column :attributes_json, :jsonb
      Float :min_lon
      Float :min_lat
      Float :max_lon
      Float :max_lat
      TrueClass :active, null: false, default: true
      DateTime :first_seen_at, null: false
      DateTime :last_seen_at, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :irwin_id, unique: true
      index [:active, :last_seen_at]
    end

    create_table(:wildfire_syncs) do
      primary_key :id
      DateTime :started_at, null: false
      DateTime :finished_at
      TrueClass :success, null: false, default: false
      Integer :points_http_status
      Integer :perimeters_http_status
      Integer :incident_count
      Integer :perimeter_count
      String :error_class
      String :error_message, text: true
      Integer :duration_ms
      column :metadata_json, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :finished_at
      index [:success, :finished_at]
    end
  end
end
