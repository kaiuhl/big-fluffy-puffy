Sequel.migration do
  change do
    alter_table(:wildfire_incidents) do
      add_column :information_url, String
    end
  end
end
