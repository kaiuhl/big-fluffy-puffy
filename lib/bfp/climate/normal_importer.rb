require "csv"
require "json"

module BFP
  module Climate
    class NormalImporter
      DEFAULT_CSV_PATH = File.join(BFP.root, "data/climate/prism_1991_2020_tmin_forest_elevation_bands.csv")
      DEFAULT_MANIFEST_PATH = File.join(BFP.root, "data/climate/prism_1991_2020_tmin_manifest.json")

      REQUIRED_COLUMNS = %w[
        land_unit_slug
        climate_dataset_slug
        month
        elevation_min_ft
        elevation_band_label
        mean_low_f
        sample_cell_count
      ].freeze

      def initialize(csv_path: DEFAULT_CSV_PATH, manifest_path: DEFAULT_MANIFEST_PATH)
        @csv_path = csv_path
        @manifest_path = manifest_path
      end

      def import
        raise "Missing climate normals CSV: #{@csv_path}" unless File.file?(@csv_path)
        raise "Missing climate normals manifest: #{@manifest_path}" unless File.file?(@manifest_path)

        manifest = JSON.parse(File.read(@manifest_path))
        dataset = nil
        imported = 0

        BFP.db.transaction do
          dataset = upsert_dataset(manifest.fetch("dataset"))
          land_units_by_slug = BFP::FireRestrictions::LandUnit.all.to_h { |land_unit| [land_unit.slug, land_unit] }

          CSV.foreach(@csv_path, headers: true) do |row|
            validate_row!(row)

            land_unit_slug = row["land_unit_slug"]
            land_unit = land_units_by_slug.fetch(land_unit_slug) do
              raise "Climate normal references unknown land unit: #{land_unit_slug}"
            end

            raise "Unexpected dataset slug #{row["climate_dataset_slug"]}" unless row["climate_dataset_slug"] == dataset.slug

            upsert_normal(dataset, land_unit, row)
            imported += 1
          end
        end

        {dataset: dataset.slug, rows: imported}
      end

      private

      def upsert_dataset(attributes)
        now = Time.now
        slug = attributes.fetch("slug")
        dataset = Dataset.first(slug: slug)
        values = {
          slug: slug,
          name: attributes.fetch("name"),
          provider: attributes.fetch("provider"),
          variable: attributes.fetch("variable"),
          normal_period_start_year: integer_value(attributes.fetch("normal_period_start_year")),
          normal_period_end_year: integer_value(attributes.fetch("normal_period_end_year")),
          spatial_resolution_m: optional_integer(attributes["spatial_resolution_m"]),
          source_url: attributes["source_url"],
          citation: attributes["citation"],
          metadata_json: BFP::FireRestrictions::Jsonb.wrap(attributes.fetch("metadata", {})),
          updated_at: now
        }

        if dataset
          dataset.update(values)
          dataset
        else
          Dataset.create(values.merge(created_at: now))
        end
      end

      def upsert_normal(dataset, land_unit, row)
        now = Time.now
        lookup = {
          land_unit_id: land_unit.id,
          climate_dataset_id: dataset.id,
          month: integer_value(row["month"]),
          elevation_min_ft: integer_value(row["elevation_min_ft"]),
          elevation_max_ft: optional_integer(row["elevation_max_ft"])
        }
        values = lookup.merge(
          elevation_band_label: row["elevation_band_label"],
          mean_low_f: decimal_string(row["mean_low_f"]),
          cold_p10_low_f: optional_decimal(row["cold_p10_low_f"]),
          warm_p90_low_f: optional_decimal(row["warm_p90_low_f"]),
          sample_cell_count: integer_value(row["sample_cell_count"]),
          area_acres: optional_decimal(row["area_acres"]),
          area_pct_of_forest: optional_decimal(row["area_pct_of_forest"]),
          metadata_json: BFP::FireRestrictions::Jsonb.wrap(json_value(row["metadata_json"])),
          updated_at: now
        )

        normal = LandUnitNormal.first(lookup)
        if normal
          normal.update(values)
        else
          LandUnitNormal.create(values.merge(created_at: now))
        end
      end

      def validate_row!(row)
        missing = REQUIRED_COLUMNS.select { |column| row[column].to_s.strip.empty? }
        raise "Climate normals row missing #{missing.join(", ")}" unless missing.empty?
      end

      def json_value(value)
        return {} if value.to_s.strip.empty?

        JSON.parse(value)
      end

      def decimal_string(value)
        value.to_s.strip
      end

      def optional_decimal(value)
        stripped = value.to_s.strip
        return if stripped.empty?

        stripped
      end

      def integer_value(value)
        Integer(value)
      end

      def optional_integer(value)
        stripped = value.to_s.strip
        return if stripped.empty?

        Integer(stripped)
      end
    end
  end
end
