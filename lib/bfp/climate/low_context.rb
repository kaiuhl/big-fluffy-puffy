require "date"

module BFP
  module Climate
    class LowContext
      DEFAULT_DATASET_SLUG = "prism-1991-2020-tmin-800m"
      MIN_DISPLAY_SAMPLE_CELLS = 5
      MIN_DISPLAY_AREA_PCT = 0.5
      MONTH_NAMES = Date::MONTHNAMES.freeze

      def self.for_land_units(land_units, month: Date.today.month, dataset_slug: DEFAULT_DATASET_SLUG)
        new(month: month, dataset_slug: dataset_slug).for_land_units(land_units)
      end

      def initialize(month:, dataset_slug: DEFAULT_DATASET_SLUG)
        @month = Integer(month)
        @dataset_slug = dataset_slug
      end

      def for_land_units(land_units)
        ids = land_units.map(&:id)
        return {} if ids.empty?

        dataset = Dataset.first(slug: @dataset_slug)
        return {} unless dataset

        rows = LandUnitNormal
          .where(climate_dataset_id: dataset.id, land_unit_id: ids, month: @month)
          .order(:land_unit_id, :elevation_min_ft)
          .all

        rows.group_by(&:land_unit_id).transform_values do |grouped_rows|
          serialize(dataset, grouped_rows)
        end.compact
      end

      private

      def serialize(dataset, rows)
        bands = rows.filter_map { |row| serialize_band(row) }
        return if bands.empty?

        {
          month: @month,
          month_name: MONTH_NAMES.fetch(@month),
          dataset_slug: dataset.slug,
          source_label: "#{dataset.provider} #{dataset.normal_period_start_year}-#{dataset.normal_period_end_year} normals",
          source_url: dataset.source_url,
          bands: bands
        }
      end

      def serialize_band(row)
        return unless displayable?(row)

        {
          label: row.elevation_band_label,
          elevation_min_ft: row.elevation_min_ft,
          elevation_max_ft: row.elevation_max_ft,
          mean_low_f: rounded_float(row.mean_low_f),
          cold_p10_low_f: rounded_float(row.cold_p10_low_f),
          warm_p90_low_f: rounded_float(row.warm_p90_low_f),
          sample_cell_count: row.sample_cell_count,
          area_pct_of_forest: rounded_float(row.area_pct_of_forest)
        }
      end

      def displayable?(row)
        row.sample_cell_count.to_i >= MIN_DISPLAY_SAMPLE_CELLS &&
          row.area_pct_of_forest.to_f >= MIN_DISPLAY_AREA_PCT
      end

      def rounded_float(value)
        return if value.nil?

        value.to_f.round(1)
      end
    end
  end
end
