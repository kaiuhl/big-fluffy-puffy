require_relative "../../spec_helper"
require "bfp/places/normalizer"

RSpec.describe BFP::Places::Normalizer do
  it "normalizes common outdoor abbreviations for search" do
    expect(described_class.normalize("Mt. Hood NF")).to eq("mount hood national forest")
    expect(described_class.normalize("Eagle Creek Trl")).to eq("eagle creek trail")
    expect(described_class.normalize("Wahtum Lk")).to eq("wahtum lake")
    expect(described_class.normalize("Campgrounds")).to eq("campground")
  end

  it "slugifies place names into stable URL fragments" do
    expect(described_class.slugify("Mt. Hood National Forest")).to eq("mount-hood")
    expect(described_class.slugify("Burnt Lake #1")).to eq("burnt-lake-1")
  end
end
