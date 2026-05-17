Sequel.migration do
  up do
    alter_table(:places) do
      add_column :metadata_json, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
    end
  end

  down do
    alter_table(:places) do
      drop_column :metadata_json
    end
  end
end
