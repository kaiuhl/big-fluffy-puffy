module BFP
  module Climate
    class NormalValidator
      DEFAULT_DATASET_SLUG = LowContext::DEFAULT_DATASET_SLUG

      def initialize(dataset_slug: DEFAULT_DATASET_SLUG)
        @dataset_slug = dataset_slug
      end

      def report
        dataset = Dataset.first(slug: @dataset_slug)
        return "Climate dataset #{@dataset_slug} is not imported." unless dataset

        rows = LandUnitNormal.where(climate_dataset_id: dataset.id).all
        active_land_units = BFP::FireRestrictions::LandUnit.where(active: true).order(:slug).all
        lines = []
        lines << "Dataset: #{dataset.slug}"
        lines << "Rows: #{rows.length}"
        lines << "Active land units: #{active_land_units.length}"
        lines << "Missing land-unit months: #{missing_forest_months(active_land_units, rows).length}"

        warnings = validation_warnings(active_land_units, rows)
        if warnings.empty?
          lines << "Warnings: none"
        else
          lines << "Warnings:"
          warnings.each { |warning| lines << "  - #{warning}" }
        end

        lines.join("\n")
      end

      private

      def missing_forest_months(land_units, rows)
        months_by_land_unit_id = rows.group_by(&:land_unit_id).transform_values do |grouped_rows|
          grouped_rows.map(&:month).uniq
        end

        land_units.flat_map do |land_unit|
          present_months = months_by_land_unit_id.fetch(land_unit.id, [])
          (1..12).reject { |month| present_months.include?(month) }.map { |month| [land_unit.slug, month] }
        end
      end

      def validation_warnings(land_units, rows)
        warnings = []
        rows.each do |row|
          low = row.mean_low_f.to_f
          warnings << "#{land_unit_slug(land_units, row.land_unit_id)} month #{row.month} #{row.elevation_band_label} has implausible mean low #{low.round(1)}F" unless (-60.0..90.0).cover?(low)
        end

        rows.group_by { |row| [row.land_unit_id, row.month] }.each do |(land_unit_id, month), grouped_rows|
          ordered = grouped_rows.sort_by(&:elevation_min_ft)
          next if ordered.length < 2

          lowest = ordered.first.mean_low_f.to_f
          highest = ordered.last.mean_low_f.to_f
          if highest > lowest + 5.0
            warnings << "#{land_unit_slug(land_units, land_unit_id)} month #{month} top band is more than 5F warmer than low band"
          end
        end

        warnings
      end

      def land_unit_slug(land_units, id)
        land_units.find { |land_unit| land_unit.id == id }&.slug || "land_unit_id=#{id}"
      end
    end
  end
end
