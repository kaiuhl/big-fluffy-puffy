require "json"
require "tmpdir"
require_relative "../../spec_helper"
require_relative "../../../config/boot"
require_relative "../../../lib/bfp/fire_restrictions/forest_map_presenter"

RSpec.describe BFP::FireRestrictions::ForestMapPresenter do
  it "adds a forest-wide active restriction feature for published full restrictions" do
    Dir.mktmpdir do |dir|
      presenter = described_class.new(
        slug: "mt-hood",
        boundary_path: boundary_path(dir),
        forest_presenter: fake_forest_presenter(
          forest_detail(
            forest: forest_record(
              status: "full",
              campfire_policy: "prohibited",
              review_status: "auto_accepted",
              summary: "Campfires are prohibited across the forest."
            ),
            localized_restrictions: [localized_rule]
          )
        )
      )

      features = presenter.geojson.fetch(:features)
      forestwide = features.find { |feature| feature.dig(:properties, :kind) == "forestwide_restriction" }

      expect(features.map { |feature| feature.dig(:properties, :kind) }).to eq(
        %w[land_unit_boundary forestwide_restriction localized_restriction]
      )
      expect(forestwide.fetch(:geometry)).to eq(boundary_geometry)
      expect(forestwide.dig(:properties, :map_status)).to eq("forestwide_active")
      expect(forestwide.dig(:properties, :status)).to eq("full")
      expect(forestwide.dig(:properties, :campfire_policy)).to eq("prohibited")
      expect(forestwide.dig(:properties, :restriction_detail)).to eq("Campfires are prohibited across the forest.")
    end
  end

  it "does not paint partial localized rollups as forest-wide restrictions" do
    Dir.mktmpdir do |dir|
      presenter = described_class.new(
        slug: "mt-hood",
        boundary_path: boundary_path(dir),
        forest_presenter: fake_forest_presenter(
          forest_detail(
            forest: forest_record(status: "partial", campfire_policy: "prohibited", review_status: "accepted"),
            localized_restrictions: [localized_rule]
          )
        )
      )

      kinds = presenter.geojson.fetch(:features).map { |feature| feature.dig(:properties, :kind) }

      expect(kinds).to eq(%w[land_unit_boundary localized_restriction])
    end
  end

  def fake_forest_presenter(detail)
    Struct.new(:detail) do
      def forest(_slug)
        detail
      end
    end.new(detail)
  end

  def boundary_path(dir)
    path = File.join(dir, "boundaries.geojson")
    File.write(
      path,
      JSON.generate(
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: boundary_geometry,
            properties: {slug: "mt-hood"}
          }
        ]
      )
    )
    path
  end

  def forest_detail(forest:, localized_restrictions:)
    {
      land_unit: forest,
      forest: forest,
      localized_restrictions: localized_restrictions
    }
  end

  def forest_record(overrides = {})
    {
      slug: "mt-hood",
      name: "Mt. Hood National Forest",
      land_unit_url: "/fire-restrictions/mt-hood",
      forest_url: "/fire-restrictions/mt-hood",
      unit_type: "national_forest",
      agency: "USFS",
      status: "none",
      campfire_policy: "allowed",
      review_status: "auto_accepted",
      affected_area: "Mt. Hood National Forest",
      summary: "No restrictions are published.",
      source_url: "https://example.test/alerts",
      source_title: "Alerts",
      last_checked_at: "2026-06-30T17:14:16Z"
    }.merge(overrides)
  end

  def localized_rule
    {
      id: 12,
      slug: "burnt-lake",
      title: "Burnt Lake",
      status: "year_round",
      duration_type: "permanent",
      campfire_policy: "prohibited",
      gas_stove_policy: "unknown",
      alcohol_stove_policy: "unknown",
      solid_fuel_stove_policy: "unknown",
      wood_stove_policy: "unknown",
      affected_area: "Burnt Lake",
      geometry_json: localized_geometry,
      geometry_source_type: "derived_nhd_waterbody_buffer",
      geometry_provenance: {},
      source_url: "https://example.test/burnt-lake",
      source_title: "Burnt Lake rules"
    }
  end

  def boundary_geometry
    {
      "type" => "Polygon",
      "coordinates" => [
        [
          [-122.0, 45.0],
          [-121.0, 45.0],
          [-121.0, 46.0],
          [-122.0, 45.0]
        ]
      ]
    }
  end

  def localized_geometry
    {
      "type" => "Polygon",
      "coordinates" => [
        [
          [-121.8, 45.3],
          [-121.7, 45.3],
          [-121.7, 45.4],
          [-121.8, 45.3]
        ]
      ]
    }
  end
end
