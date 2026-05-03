require "csv"
require "json"
require "tmpdir"
require_relative "../../spec_helper"

RSpec.describe "climate normal importer", :db do
  before do
    skip "Set RUN_DB_SPECS=true with TEST_DATABASE_URL to run database integration specs." unless ENV["RUN_DB_SPECS"] == "true"
  end

  it "imports committed climate normals idempotently and exposes current-month context" do
    prepare_climate_database

    land_unit = BFP::FireRestrictions::LandUnit.first(slug: "willamette")

    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, "manifest.json")
      csv_path = File.join(dir, "normals.csv")

      File.write(manifest_path, JSON.pretty_generate(fixture_manifest))
      CSV.open(csv_path, "w", write_headers: true, headers: csv_headers) do |csv|
        csv << fixture_row(land_unit.slug, sample_cell_count: 12, area_pct_of_forest: 4.2)
        csv << fixture_row(land_unit.slug, elevation_min_ft: 6000, elevation_max_ft: 8000, elevation_band_label: "6,000-8,000 ft", mean_low_f: 31.2, sample_cell_count: 2, area_pct_of_forest: 0.2)
      end

      importer = BFP::Climate::NormalImporter.new(csv_path: csv_path, manifest_path: manifest_path)

      expect(importer.import).to eq(dataset: "prism-1991-2020-tmin-800m", rows: 2)
      expect(importer.import).to eq(dataset: "prism-1991-2020-tmin-800m", rows: 2)
    end

    expect(BFP::Climate::Dataset.count).to eq(1)
    expect(BFP::Climate::LandUnitNormal.count).to eq(2)
    expect(BFP::Climate::LandUnitNormal.first.metadata.to_h).to include("fixture" => true)

    forest = BFP::FireRestrictions::StatusPresenter.new(month: 5)
      .forests
      .find { |row| row[:slug] == land_unit.slug }

    expect(forest[:climate_low_context]).to include(
      month: 5,
      month_name: "May",
      dataset_slug: "prism-1991-2020-tmin-800m"
    )
    expect(forest[:climate_low_context].fetch(:bands).length).to eq(1)
    expect(forest[:climate_low_context].fetch(:bands).first).to include(
      label: "4,000-6,000 ft",
      mean_low_f: 39.7,
      sample_cell_count: 12
    )
  end

  def prepare_climate_database
    require_relative "../../../config/boot"
    require "sequel/extensions/migration"

    Sequel::Migrator.run(BFP.db, File.join(BFP.root, "db/migrations"))
    require "bfp/fire_restrictions"
    require "bfp/climate"
    BFP.db.run(<<~SQL)
      TRUNCATE
        land_unit_climate_normals,
        climate_datasets,
        restriction_statuses,
        restriction_observations,
        source_fetches,
        source_documents,
        restriction_sources,
        land_units
      RESTART IDENTITY CASCADE
    SQL
    BFP::FireRestrictions::SourceSeeder.new.seed
  end

  def fixture_manifest
    {
      dataset: {
        slug: "prism-1991-2020-tmin-800m",
        name: "PRISM 1991-2020 Monthly Minimum Temperature Normals",
        provider: "PRISM",
        variable: "tmin",
        normal_period_start_year: 1991,
        normal_period_end_year: 2020,
        spatial_resolution_m: 800,
        source_url: "https://prism.oregonstate.edu/normals/",
        citation: "Fixture citation",
        metadata: {"fixture" => true}
      }
    }
  end

  def csv_headers
    %w[
      land_unit_slug
      land_unit_name
      climate_dataset_slug
      month
      elevation_min_ft
      elevation_max_ft
      elevation_band_label
      mean_low_f
      cold_p10_low_f
      warm_p90_low_f
      sample_cell_count
      area_acres
      area_pct_of_forest
      metadata_json
    ]
  end

  def fixture_row(
    slug,
    elevation_min_ft: 4000,
    elevation_max_ft: 6000,
    elevation_band_label: "4,000-6,000 ft",
    mean_low_f: 39.7,
    sample_cell_count: 12,
    area_pct_of_forest: 4.2
  )
    {
      "land_unit_slug" => slug,
      "land_unit_name" => "Willamette National Forest",
      "climate_dataset_slug" => "prism-1991-2020-tmin-800m",
      "month" => 5,
      "elevation_min_ft" => elevation_min_ft,
      "elevation_max_ft" => elevation_max_ft,
      "elevation_band_label" => elevation_band_label,
      "mean_low_f" => mean_low_f,
      "cold_p10_low_f" => mean_low_f - 3,
      "warm_p90_low_f" => mean_low_f + 3,
      "sample_cell_count" => sample_cell_count,
      "area_acres" => 1200,
      "area_pct_of_forest" => area_pct_of_forest,
      "metadata_json" => JSON.generate("fixture" => true)
    }
  end
end
