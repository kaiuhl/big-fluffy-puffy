require_relative "../../spec_helper"
require "bfp/places/searcher"

RSpec.describe BFP::Places::Searcher do
  let(:name_row_class) { Struct.new(:normalized_name, :weight, :name) }
  let(:place_row_class) { Struct.new(:search_rank, :place_type) }
  let(:land_unit_class) { Struct.new(:slug, :name) }

  it "ranks exact destination matches above prefix and token matches" do
    searcher = described_class.new
    place = place_row_class.new(100, "lake")
    exact = name_row_class.new("burnt lake", 100, "Burnt Lake")
    prefix = name_row_class.new("burnt lake trail", 100, "Burnt Lake Trail")
    token = name_row_class.new("mount hood burnt lake", 100, "Mount Hood Burnt Lake")

    expect(searcher.send(:score_name, exact, place, "burnt lake")).to be > searcher.send(:score_name, prefix, place, "burnt lake")
    expect(searcher.send(:score_name, prefix, place, "burnt lake")).to be > searcher.send(:score_name, token, place, "burnt lake")
  end

  it "adds county and map context to duplicate place subtitles" do
    searcher = described_class.new
    place = Struct.new(:place_type, :state_code, :metadata).new(
      "lake",
      "or",
      {"county_name" => "Linn", "map_name" => "Marion Lake"}
    )

    subtitle = searcher.send(:subtitle_for, place, [land_unit_class.new("willamette", "Willamette National Forest")])

    expect(subtitle).to eq("Lake / Willamette National Forest / Oregon / Linn County / Marion Lake quad")
  end

  it "boosts monitored places above same-name unmonitored records" do
    searcher = described_class.new

    expect(searcher.send(:context_score, [land_unit_class.new("gifford-pinchot", "Gifford Pinchot National Forest")], 0)).to be > searcher.send(:context_score, [], 0)
  end

  it "boosts duplicate place names when query terms match forest context" do
    searcher = described_class.new
    place = Struct.new(:state_code, :metadata).new("wa", {})
    gifford = [land_unit_class.new("gifford-pinchot", "Gifford Pinchot National Forest")]
    willamette = [land_unit_class.new("willamette", "Willamette National Forest")]

    expect(searcher.send(:context_query_score, "bear lake gifford", "bear lake", place, gifford)).to be > searcher.send(:context_query_score, "bear lake gifford", "bear lake", place, willamette)
  end

  it "recognizes campground category queries" do
    searcher = described_class.new
    campground = Struct.new(:place_type).new("campground")
    lake = Struct.new(:place_type).new("lake")
    category_types = searcher.send(:category_place_types, "campground")

    expect(category_types).to eq(["campground"])
    expect(searcher.send(:category_place_types, "camping")).to eq(["campground"])
    expect(searcher.send(:type_query_score, campground, category_types)).to be > searcher.send(:type_query_score, lake, category_types)
  end

  it "uses source forest metadata in subtitles before spatial resolution runs" do
    searcher = described_class.new
    place = Struct.new(:place_type, :state_code, :metadata).new(
      "campground",
      nil,
      {"forest_name" => "Willamette National Forest"}
    )

    expect(searcher.send(:subtitle_for, place, [])).to eq("Campground / Willamette National Forest")
  end
end
