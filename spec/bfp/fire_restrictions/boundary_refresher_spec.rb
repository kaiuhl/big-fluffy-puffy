require "json"
require "tmpdir"
require "yaml"
require_relative "../../spec_helper"
require_relative "../../../config/boot"
require_relative "../../../lib/bfp/fire_restrictions/boundary_refresher"

RSpec.describe BFP::FireRestrictions::BoundaryRefresher do
  it "combines USFS forest boundaries with NPS multi-code park complex boundaries" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "sources.yml")
      output_path = File.join(dir, "boundaries.geojson")
      File.write(config_path, config.to_yaml)

      refresher = described_class.new(config_path: config_path, output_path: output_path)
      allow(refresher).to receive(:fetch_usfs_source_features).and_return([usfs_feature])
      allow(refresher).to receive(:fetch_nps_source_features).with(%w[NOCA ROLA LACH]).and_return(nps_features)

      expect(refresher.refresh).to eq(2)

      data = JSON.parse(File.read(output_path))
      features = data.fetch("features").to_h { |feature| [feature.dig("properties", "slug"), feature] }

      expect(data.fetch("name")).to eq("BFP fire restriction land unit boundaries")
      expect(features.keys).to match_array(%w[deschutes north-cascades])
      expect(features.fetch("deschutes").dig("properties", "source_url")).to include("EDW_ForestSystemBoundaries")
      expect(features.fetch("north-cascades").dig("properties", "agency")).to eq("NPS")
      expect(features.fetch("north-cascades").dig("properties", "nps_unit_codes")).to eq(%w[NOCA ROLA LACH])
      expect(features.fetch("north-cascades").fetch("geometry")).to include(
        "type" => "MultiPolygon"
      )
      expect(features.fetch("north-cascades").dig("geometry", "coordinates").length).to eq(4)
    end
  end

  def config
    {
      "land_units" => [
        {
          "slug" => "deschutes",
          "name" => "Deschutes National Forest",
          "active" => true
        },
        {
          "slug" => "north-cascades",
          "name" => "North Cascades National Park Service Complex",
          "agency" => "NPS",
          "region_code" => "PWR",
          "boundary_source_codes" => %w[NOCA ROLA LACH],
          "active" => true
        }
      ]
    }
  end

  def usfs_feature
    {
      "type" => "Feature",
      "geometry" => polygon(0),
      "properties" => {
        "forestname" => "Deschutes National Forest",
        "region" => "06",
        "forestnumber" => "601",
        "gis_acres" => 1_000
      }
    }
  end

  def nps_features
    [
      nps_feature("NOCA", "North Cascades National Park", polygon(1)),
      nps_feature("ROLA", "Ross Lake National Recreation Area", polygon(2)),
      nps_feature("LACH", "Lake Chelan National Recreation Area", multipolygon(3, 4))
    ]
  end

  def nps_feature(code, name, geometry)
    {
      "type" => "Feature",
      "geometry" => geometry,
      "properties" => {
        "UNIT_CODE" => code,
        "UNIT_NAME" => name,
        "PARKNAME" => name,
        "UNIT_TYPE" => "National Parks",
        "STATE" => "WA",
        "REGION" => "PWR"
      }
    }
  end

  def polygon(offset)
    {
      "type" => "Polygon",
      "coordinates" => [
        [
          [offset, 0],
          [offset + 1, 0],
          [offset + 1, 1],
          [offset, 0]
        ]
      ]
    }
  end

  def multipolygon(*offsets)
    {
      "type" => "MultiPolygon",
      "coordinates" => offsets.map { |offset| polygon(offset).fetch("coordinates") }
    }
  end
end
