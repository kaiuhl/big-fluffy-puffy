Sequel.migration do
  change do
    create_table(:restriction_status_changes) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      foreign_key :restriction_observation_id, :restriction_observations, on_delete: :set_null
      String :from_status
      String :from_campfire_policy
      String :to_status, null: false
      String :to_campfire_policy, null: false
      String :summary, text: true
      String :source_url
      String :source_title
      String :order_number
      Date :effective_start
      Date :effective_end
      DateTime :changed_at, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :changed_at
      index [:land_unit_id, :changed_at]
    end
  end
end
