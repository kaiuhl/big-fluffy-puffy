require "yaml"
require_relative "../../spec_helper"

RSpec.describe "fire restriction source catalog" do
  let(:config) { YAML.load_file(File.expand_path("../../../config/fire_restriction_sources.yml", __dir__)) }
  let(:units) { config.fetch("land_units") }
  let(:active_unit_slugs) do
    %w[
      colville
      deschutes
      fremont-winema
      gifford-pinchot
      malheur
      mt-baker-snoqualmie
      mt-hood
      ochoco-crooked-river
      okanogan-wenatchee
      olympic
      rogue-river-siskiyou
      siuslaw
      umatilla
      umpqua
      wallowa-whitman
      willamette
      north-cascades
      mount-rainier
      olympic-national-park
      crater-lake
      klamath
      six-rivers
      shasta-trinity
      mendocino
      modoc
      lassen
      lassen-volcanic
      plumas
    ]
  end
  let(:inactive_unit_slugs) { %w[tahoe eldorado lake-tahoe-basin] }
  let(:core_source_suffixes) { %w[fire fire-info alerts releases] }

  it "tracks every active forest and national park in the PNW and Northern California launch market" do
    active_slugs = units.select { |unit| unit.fetch("active", true) }.map { |unit| unit.fetch("slug") }

    expect(active_slugs).to match_array(active_unit_slugs)
  end

  it "keeps the Tahoe extension units present but inactive" do
    inactive_slugs = units.reject { |unit| unit.fetch("active", true) }.map { |unit| unit.fetch("slug") }

    expect(inactive_slugs).to match_array(inactive_unit_slugs)
  end

  it "has unique land-unit and generated source slugs" do
    unit_slugs = units.map { |unit| unit.fetch("slug") }
    source_slugs = units.flat_map { |unit| generated_sources(unit).map { |source| source.fetch("slug") } }

    expect(unit_slugs).to eq(unit_slugs.uniq)
    expect(source_slugs).to eq(source_slugs.uniq)
  end

  it "gives every Forest Service unit the core Forest Service source pages" do
    usfs_units.each do |unit|
      aggregate_failures(unit.fetch("slug")) do
        source_slugs = generated_sources(unit).map { |source| source.fetch("slug") }

        core_source_suffixes.each do |suffix|
          expect(source_slugs).to include("#{unit.fetch("slug")}-#{suffix}")
        end
      end
    end
  end

  it "uses parseable HTTPS URLs and parser keys for every generated source" do
    units.each do |unit|
      generated_sources(unit).each do |source|
        aggregate_failures(source.fetch("slug")) do
          expect(source.fetch("url")).to start_with("https://")
          expect(source.fetch("url")).not_to match(/\s/)
          expect(source.fetch("source_type")).not_to be_empty
          expect(source.fetch("parser_key")).not_to be_empty
        end
      end
    end
  end

  it "includes the Central Oregon ArcGIS restriction layer for both Central Oregon units" do
    arcgis_sources = generated_sources(unit("deschutes")) + generated_sources(unit("ochoco-crooked-river"))
    arcgis_sources = arcgis_sources.select { |source| source.fetch("source_type") == "arcgis_feature_layer" }

    expect(arcgis_sources.map { |source| source.fetch("slug") }).to match_array(
      %w[deschutes-central-oregon-restrictions ochoco-central-oregon-restrictions]
    )
    expect(arcgis_sources).to all(include("parser_key" => "central_oregon_arcgis"))
    expect(arcgis_sources).to all(satisfy { |source| source.dig("metadata_json", "auto_publish") == true })
  end

  it "tracks the PNW national parks with NPS API alerts and official page sources" do
    expect(nps_units.map { |unit| unit.fetch("slug") }).to match_array(
      %w[
        north-cascades
        mount-rainier
        olympic-national-park
        crater-lake
        lassen-volcanic
      ]
    )

    nps_units.each do |unit|
      sources = generated_sources(unit)
      alert_source = sources.find { |source| source.fetch("source_type") == "nps_alerts_api" }

      aggregate_failures(unit.fetch("slug")) do
        expect(unit.fetch("source_paths")).to eq([])
        expect(unit.fetch("agency")).to eq("NPS")
        expect(unit.fetch("boundary_source_codes")).not_to be_empty
        expect(alert_source).to include(
          "authority" => "official_nps",
          "parser_key" => "nps_alerts"
        )
        expect(alert_source.fetch("url")).to start_with("https://developer.nps.gov/api/v1/alerts?parkCode=")
        expect(sources.count { |source| source.fetch("authority") == "official_nps" }).to be >= 3
      end
    end
  end

  it "tracks official NPS fire-use regulation pages for parks with durable backcountry rules" do
    sources = [
      generated_sources(unit("north-cascades")).find { |source| source.fetch("slug") == "north-cascades-wilderness-trip-planner" },
      generated_sources(unit("olympic-national-park")).find { |source| source.fetch("slug") == "olympic-national-park-wilderness-regulations" },
      generated_sources(unit("lassen-volcanic")).find { |source| source.fetch("slug") == "lassen-volcanic-fire-regulations" }
    ]

    expect(sources).to all(include("authority" => "official_nps", "source_type" => "nps_fire_page"))
    expect(sources).to all(satisfy { |source| source.dig("metadata_json", "auto_publish") == true })
  end

  it "tracks Colville's maintained current fire restrictions page" do
    source = generated_sources(unit("colville")).find { |candidate| candidate.fetch("slug") == "colville-fire-restrictions" }

    expect(source).to include(
      "source_type" => "fs_fire_info_page",
      "url" => "https://www.fs.usda.gov/r06/colville/fire/fire-restrictions",
      "parser_key" => "usfs_html"
    )
  end

  def unit(slug)
    units.find { |candidate| candidate.fetch("slug") == slug }
  end

  def usfs_units
    units.reject { |unit| unit.fetch("agency", "USFS") == "NPS" }
  end

  def nps_units
    units.select { |unit| unit.fetch("agency", "USFS") == "NPS" }
  end

  def generated_sources(unit_config)
    defaults = config.fetch("defaults")
    default_paths = unit_config.key?("source_paths") ? unit_config.fetch("source_paths") : defaults.fetch("source_paths")
    default_interval = defaults.fetch("poll_interval_minutes")

    path_sources = (default_paths + unit_config.fetch("extra_source_paths", [])).map do |source_path|
      source_from_path(unit_config, source_path, default_interval)
    end

    explicit_sources = unit_config.fetch("sources", []).map do |source|
      source.merge("poll_interval_minutes" => source.fetch("poll_interval_minutes", default_interval))
    end

    path_sources + explicit_sources
  end

  def source_from_path(unit_config, source_path, default_interval)
    {
      "slug" => "#{unit_config.fetch("slug")}-#{source_path.fetch("key")}",
      "name" => source_path.fetch("name"),
      "source_type" => source_path.fetch("source_type"),
      "url" => "#{unit_config.fetch("official_url").sub(%r{/\z}, "")}#{source_path.fetch("path")}",
      "parser_key" => source_path.fetch("parser_key"),
      "poll_interval_minutes" => source_path.fetch("poll_interval_minutes", default_interval)
    }
  end
end
