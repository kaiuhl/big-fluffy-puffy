Sequel.migration do
  change do
    alter_table(:restriction_status_changes) do
      add_column :origin, String, null: false, default: "resolver"
    end
  end
end
