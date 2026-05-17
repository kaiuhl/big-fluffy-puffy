require "yaml"
require_relative "../../spec_helper"
require "bfp/places/normalizer"

RSpec.describe "BFP curated place catalog" do
  let(:catalog) { YAML.load_file(File.expand_path("../../../config/place_manual.yml", __dir__)) }
  let(:places) { catalog.fetch("places") }
  let(:common_queries) do
    [
      "Burnt Lake",
      "Wahtum Lake",
      "Ramona Falls",
      "Paradise Park",
      "Jefferson Park",
      "Eagle Creek Trail",
      "Timberline Trail",
      "McNeil Point",
      "Elk Cove",
      "Elk Meadows",
      "Lost Lake Campground",
      "Trillium Lake",
      "Mirror Lake Trail",
      "Tilly Jane Trailhead",
      "Frog Lake Campground",
      "Tamolitch Blue Pool",
      "Opal Creek",
      "Marion Lake",
      "Pamelia Lake",
      "Waldo Lake",
      "Green Lakes Trail",
      "Devils Lake Campground",
      "Sparks Lake",
      "Todd Lake",
      "Moraine Lake",
      "South Sister",
      "Broken Top",
      "Metolius River",
      "Camp Sherman",
      "Scott Lake Campground",
      "Three Sisters Wilderness",
      "Colchuck Lake",
      "The Enchantments",
      "Snow Lakes Trail",
      "Eightmile Lake",
      "Stuart Lake Trailhead",
      "Alpine Lakes Wilderness",
      "Goat Rocks Wilderness",
      "Snowgrass Flat",
      "Goat Lake Goat Rocks",
      "Packwood Lake",
      "Mount Adams",
      "Chain Lakes Trail",
      "Artist Point",
      "Heather Meadows",
      "Maple Pass Loop",
      "Blue Lake North Cascades",
      "Cascade Pass",
      "Hoh River Trail",
      "Enchanted Valley",
      "Sol Duc Falls",
      "Lake Ozette",
      "Shi Shi Beach",
      "Trinity Alps Wilderness",
      "Canyon Creek Lakes",
      "Caribou Lakes",
      "Devils Punchbowl",
      "Castle Lake",
      "Mount Shasta Wilderness",
      "Heart Lake Mount Shasta",
      "Russian Wilderness"
    ]
  end

  it "covers at least fifty common PNW outdoor destination queries" do
    missing = common_queries.reject { |query| catalog_matches_query?(query) }

    expect(places.length).to be >= 50
    expect(common_queries.length).to be >= 50
    expect(missing).to eq([])
  end

  it "keeps launch places usable for spatial seeding" do
    required_types = %w[campground destination lake trail trailhead wilderness]
    place_types = places.map { |place| place.fetch("place_type") }.uniq
    invalid_places = places.reject do |place|
      place["slug"].to_s != "" &&
        place["name"].to_s != "" &&
        place["place_type"].to_s != "" &&
        place["state_code"].to_s.match?(/\A(or|wa|ca)\z/) &&
        place["latitude"].is_a?(Numeric) &&
        place["longitude"].is_a?(Numeric)
    end

    expect(place_types).to include(*required_types)
    expect(invalid_places).to eq([])
  end

  def catalog_matches_query?(query)
    matching_place_slugs(query).any?
  end

  def matching_place_slugs(query)
    normalized_query = BFP::Places::Normalizer.normalize(query)
    query_tokens = normalized_query.split

    places.filter_map do |place|
      names = [place.fetch("name"), *Array(place["aliases"])].map { |name| BFP::Places::Normalizer.normalize(name) }
      next unless names.any? do |name|
        name == normalized_query ||
          name.start_with?(normalized_query) ||
          normalized_query.start_with?(name) ||
          query_tokens.all? { |token| name.include?(token) }
      end

      place.fetch("slug")
    end
  end
end
