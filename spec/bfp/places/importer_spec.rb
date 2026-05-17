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

  def gnis_fixture
    <<~TXT
      feature_id|feature_name|feature_class|state_name|county_name|map_name|prim_lat_dec|prim_long_dec
      1141701|Eight Lakes Basin|Basin|Oregon|Linn|Marion Lake|44.5206747|-121.863397
      1144402|Jorn Lake|Lake|Oregon|Linn|Marion Lake|44.516724|-121.8662648
      1121392|Green Peak Lake|Lake|Oregon|Linn|Marion Forks|44.5209529|-121.8889535
      123|Administrative School|School|Oregon|Linn|Marion Lake|44.1|-121.1
    TXT
  end
end
