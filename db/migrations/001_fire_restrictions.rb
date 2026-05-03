Sequel.migration do
  change do
    create_table(:land_units) do
      primary_key :id
      String :slug, null: false, unique: true
      String :name, null: false
      String :unit_type, null: false
      String :agency, null: false, default: "USFS"
      String :region_code
      String :forest_slug
      foreign_key :parent_land_unit_id, :land_units, on_delete: :set_null
      String :market_bucket, null: false, default: "core_pnw"
      String :official_url
      String :boundary_source_url
      column :geometry_json, :jsonb
      TrueClass :active, null: false, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :active
      index :region_code
      index :market_bucket
    end

    create_table(:restriction_sources) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      String :slug, null: false, unique: true
      String :name, null: false
      String :source_type, null: false
      String :authority, null: false, default: "official_usfs"
      String :url, null: false
      String :parser_key, null: false, default: "usfs_html"
      Integer :poll_interval_minutes, null: false, default: 1440
      DateTime :last_checked_at
      DateTime :last_changed_at
      TrueClass :active, null: false, default: true
      column :metadata_json, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:active, :last_checked_at]
      index :source_type
      index :land_unit_id
    end

    create_table(:source_documents) do
      primary_key :id
      String :content_hash, null: false, unique: true
      String :content_type
      column :body, :bytea, null: false
      String :title
      String :canonical_url
      DateTime :modified_at
      String :extraction_status, null: false, default: "pending"
      String :extraction_error
      String :extracted_text, text: true
      column :metadata_json, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :content_hash
      index :extraction_status
    end

    create_table(:source_fetches) do
      primary_key :id
      foreign_key :restriction_source_id, :restriction_sources, null: false, on_delete: :cascade
      foreign_key :source_document_id, :source_documents, on_delete: :set_null
      DateTime :fetched_at, null: false
      Integer :http_status
      String :final_url
      String :etag
      String :last_modified
      String :content_type
      String :content_hash
      TrueClass :content_changed, null: false, default: false
      String :error_class
      String :error_message, text: true
      Integer :duration_ms
      column :metadata_json, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:restriction_source_id, :fetched_at]
      index :content_hash
      index :content_changed
    end

    create_table(:restriction_observations) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, on_delete: :cascade
      foreign_key :restriction_source_id, :restriction_sources, null: false, on_delete: :cascade
      foreign_key :source_fetch_id, :source_fetches, on_delete: :set_null
      String :status, null: false, default: "unknown"
      String :campfire_policy, null: false, default: "unknown"
      String :fire_danger_rating
      String :ifpl_level
      Date :effective_start
      Date :effective_end
      String :order_number
      String :affected_area, text: true
      column :geometry_json, :jsonb
      String :summary, text: true
      column :evidence_quotes, :jsonb
      Float :confidence, null: false, default: 0.0
      String :review_status, null: false, default: "needs_review"
      String :parser_provider
      String :parser_model_id
      String :parser_version
      String :source_url
      String :source_title
      column :needs_review_reasons, :jsonb
      column :validation_errors, :jsonb
      column :raw_output, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:land_unit_id, :created_at]
      index [:restriction_source_id, :created_at]
      index :review_status
      index :status
    end

    create_table(:restriction_statuses) do
      primary_key :id
      foreign_key :land_unit_id, :land_units, null: false, unique: true, on_delete: :cascade
      foreign_key :restriction_observation_id, :restriction_observations, on_delete: :set_null
      String :status, null: false, default: "unknown"
      String :campfire_policy, null: false, default: "unknown"
      String :fire_danger_rating
      String :ifpl_level
      Date :effective_start
      Date :effective_end
      String :order_number
      String :affected_area, text: true
      column :geometry_json, :jsonb
      String :summary, text: true
      column :evidence_quotes, :jsonb
      Float :confidence, null: false, default: 0.0
      String :review_status, null: false, default: "needs_review"
      String :source_url
      String :source_title
      DateTime :last_checked_at
      DateTime :published_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :review_status
      index :last_checked_at
    end
  end
end
