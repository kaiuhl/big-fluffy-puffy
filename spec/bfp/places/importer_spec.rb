require "tmpdir"
require "zip"
require_relative "../../spec_helper"
require_relative "../../../config/boot"
require "bfp/places/importer"

RSpec.describe BFP::Places::Importer do
  let(:gnis_config) do
    {
      "slug" => "gnis",
      "format" => "zip",
      "zip_glob" => "**/*.txt",
      "col_sep" => "|",
      "feature_class_filter" => %w[Basin Lake Summit Trail],
      "mapping" => {
        "external_id" => %w[feature_id FEATURE_ID],
        "name" => %w[feature_name FEATURE_NAME],
        "place_type" => %w[feature_class FEATURE_CLASS],
        "latitude" => %w[prim_lat_dec PRIM_LAT_DEC],
        "longitude" => %w[prim_long_dec PRIM_LONG_DEC],
        "state_code" => %w[state_alpha STATE_ALPHA],
        "state_name" => %w[state_name STATE_NAME],
        "search_rank" => 30,
        "search_rank_map" => {
          "Basin" => 48,
          "Lake" => 56,
          "Summit" => 50,
          "Trail" => 58
        },
        "place_type_map" => {
          "Basin" => "destination",
          "Lake" => "lake",
          "Summit" => "peak",
          "Trail" => "trail"
        },
        "metadata_fields" => {
          "county_name" => "county_name",
          "map_name" => "map_name",
          "source_feature_class" => "feature_class"
        },
        "confidence" => 0.82
      }
    }
  end
  let(:usfs_campground_config) do
    {
      "slug" => "usfs-campgrounds",
      "format" => "geojson",
      "mapping" => {
        "external_id" => "recareaid",
        "name" => "recareaname",
        "place_type" => "markeractivity",
        "latitude" => "latitude",
        "longitude" => "longitude",
        "source_url" => "recareaurl",
        "search_rank" => 66,
        "search_rank_map" => {
          "Campground Camping" => 66
        },
        "place_type_map" => {
          "Campground Camping" => "campground"
        },
        "metadata_fields" => {
          "forest_name" => "forestname",
          "source_activity" => "markeractivity",
          "activity_group" => "markeractivitygroup"
        },
        "confidence" => 0.84
      }
    }
  end

  it "parses modern GNIS pipe-delimited text from state ZIP downloads" do
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "DomesticNames_OR_Text.zip")
      Zip::File.open(zip_path, create: true) do |zip|
        zip.get_output_stream("Text/DomesticNames_OR.txt") { |io| io.write(gnis_fixture) }
      end

      records = described_class.new.send(:records_from_path, zip_path, gnis_config)

      expect(records.map { |record| record.fetch("name") }).to contain_exactly(
        "Eight Lakes Basin",
        "Jorn Lake",
        "Green Peak Lake"
      )
      expect(records.map { |record| [record["name"], record["place_type"], record["state_code"]] }).to include(
        ["Eight Lakes Basin", "destination", "or"],
        ["Jorn Lake", "lake", "or"],
        ["Green Peak Lake", "lake", "or"]
      )
      expect(records.find { |record| record["name"] == "Jorn Lake" }.fetch("search_rank")).to eq(56)
      expect(records.find { |record| record["name"] == "Jorn Lake" }.fetch("metadata_json")).to include(
        "county_name" => "Linn",
        "map_name" => "Marion Lake",
        "source_feature_class" => "Lake"
      )
    end
  end

  it "maps USFS campground recreation opportunity GeoJSON into campground records" do
    Dir.mktmpdir do |dir|
      geojson_path = File.join(dir, "campgrounds.geojson")
      File.write(geojson_path, JSON.generate(usfs_campground_fixture))

      records = described_class.new.send(:records_from_path, geojson_path, usfs_campground_config)

      expect(records.length).to eq(1)
      expect(records.first).to include(
        "external_id" => 63746,
        "name" => "Steamboat Falls Campground",
        "place_type" => "campground",
        "latitude" => 43.375392,
        "longitude" => -122.652453,
        "source_url" => "https://www.fs.usda.gov/recarea/umpqua/recarea/?recid=63746",
        "search_rank" => 66,
        "confidence" => 0.84
      )
      expect(records.first.fetch("metadata_json")).to include(
        "forest_name" => "Umpqua National Forest",
        "source_activity" => "Campground Camping",
        "activity_group" => "Camping & Cabins"
      )
    end
  end

  it "uses stable cache filenames for query URLs" do
    importer = described_class.new
    basename = importer.send(
      :cache_basename,
      {"slug" => "usfs-campgrounds", "format" => "geojson"},
      "https://example.test/arcgis/rest/services/Campgrounds/MapServer/0/query?f=geojson&where=1%3D1",
      "query"
    )

    expect(basename).to match(/\Ausfs-campgrounds-[0-9a-f]{12}\.geojson\z/)
  end

  it "refuses truncated ArcGIS GeoJSON responses" do
    payload = {
      "type" => "FeatureCollection",
      "features" => [],
      "properties" => {
        "exceededTransferLimit" => true
      }
    }

    expect do
      described_class.new.send(:geojson_records_from_string, JSON.generate(payload), usfs_campground_config)
    end.to raise_error(/exceeded transfer limit/)
  end

  def gnis_fixture
    <<~TXT
      feature_id|feature_name|feature_class|state_name|county_name|map_name|prim_lat_dec|prim_long_dec
      1141701|Eight Lakes Basin|Basin|Oregon|Linn|Marion Lake|44.5206747|-121.863397
      1144402|Jorn Lake|Lake|Oregon|Linn|Marion Lake|44.516724|-121.8662648
      1121392|Green Peak Lake|Lake|Oregon|Linn|Marion Forks|44.5209529|-121.8889535
      123|Administrative School|School|Oregon|Linn|Marion Lake|44.1|-121.1
    TXT
  end

  def usfs_campground_fixture
    {
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "geometry" => {
            "type" => "Point",
            "coordinates" => [-122.65246706516818, 43.375397336066641]
          },
          "properties" => {
            "recareaid" => 63746,
            "recareaname" => "Steamboat Falls Campground",
            "markeractivity" => "Campground Camping",
            "markeractivitygroup" => "Camping & Cabins",
            "forestname" => "Umpqua National Forest",
            "recareaurl" => "https://www.fs.usda.gov/recarea/umpqua/recarea/?recid=63746",
            "latitude" => "43.375392",
            "longitude" => "-122.652453"
          }
        }
      ]
    }
  end
end
