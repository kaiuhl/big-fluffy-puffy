require_relative "../../../config/boot"
require_relative "../../spec_helper"
require "bfp/wildfires/context_presenter"

WildfireIncidentDouble = Struct.new(
  :irwin_id, :name, :acres, :percent_contained, :discovered_at, :behavior,
  :latitude, :longitude, :perimeter_geometry, :min_lon, :min_lat, :max_lon, :max_lat,
  keyword_init: true
)

RSpec.describe BFP::Wildfires::ContextPresenter do
  let(:now) { Time.utc(2026, 7, 15, 12, 0, 0) }
  let(:discovered) { Time.at(1662512400).utc }
  let(:presenter) { described_class.new(now: now) }
  let(:fresh_sync) { double("WildfireSync", finished_at: now - 3600) }

  let(:near_fire) do
    latitude = 44.0 + (5 * deg_per_mile)
    WildfireIncidentDouble.new(
      irwin_id: "NEAR-0001", name: "Whisky Ridge", acres: 45.0, percent_contained: 0.0,
      discovered_at: discovered, behavior: "Smoldering", latitude: latitude, longitude: -121.0,
      perimeter_geometry: nil,
      min_lon: -121.03, min_lat: latitude - 0.03, max_lon: -120.97, max_lat: latitude + 0.03
    )
  end

  let(:perimeter_fire) do
    WildfireIncidentDouble.new(
      irwin_id: "PERI-0002", name: "Cedar Creek", acres: 12500.0, percent_contained: 35.0,
      discovered_at: discovered, behavior: "Active", latitude: 44.0, longitude: -121.0,
      perimeter_geometry: {
        "type" => "Polygon",
        "coordinates" => [[[-121.05, 43.95], [-120.95, 43.95], [-120.95, 44.05], [-121.05, 44.05], [-121.05, 43.95]]]
      },
      min_lon: -121.05, min_lat: 43.95, max_lon: -120.95, max_lat: 44.05
    )
  end

  describe "#for_point when the sync is fresh" do
    before do
      allow(presenter).to receive(:last_successful_sync).and_return(fresh_sync)
      allow(presenter).to receive(:active_incidents).and_return([near_fire])
    end

    it "returns the highest-severity tier and an as-of timestamp" do
      result = presenter.for_point(latitude: 44.0, longitude: -121.0)

      expect(result[:status]).to eq(:near)
      expect(result[:as_of]).to eq((now - 3600).iso8601)
    end

    it "shapes each incident to the frontend contract" do
      incident = presenter.for_point(latitude: 44.0, longitude: -121.0).fetch(:incidents).first

      expect(incident.keys).to contain_exactly(
        :name, :distance_miles, :acres, :percent_contained, :discovered_at, :behavior, :irwin_id
      )
      expect(incident[:name]).to eq("Whisky Ridge")
      expect(incident[:distance_miles]).to be_a(Float)
      expect(incident[:distance_miles].round(1)).to eq(incident[:distance_miles])
      expect(incident[:discovered_at]).to eq(discovered.iso8601)
      expect(incident[:irwin_id]).to eq("NEAR-0001")
    end
  end

  describe "#for_point when no incidents match" do
    it "reports :none with an as-of timestamp" do
      allow(presenter).to receive(:last_successful_sync).and_return(fresh_sync)
      allow(presenter).to receive(:active_incidents).and_return([])

      result = presenter.for_point(latitude: 44.0, longitude: -121.0)

      expect(result[:status]).to eq(:none)
      expect(result[:as_of]).to eq((now - 3600).iso8601)
      expect(result[:incidents]).to eq([])
    end
  end

  describe "staleness TTL" do
    before { allow(presenter).to receive(:active_incidents).and_return([near_fire]) }

    it "suppresses everything past the max-age window" do
      allow(presenter).to receive(:last_successful_sync).and_return(double("WildfireSync", finished_at: now - (7 * 3600)))

      expect(presenter.for_point(latitude: 44.0, longitude: -121.0)).to eq(status: :stale, as_of: nil, incidents: [])
      expect(presenter.map_features(latitude: 44.0, longitude: -121.0)).to eq([])
    end

    it "is stale when there has never been a successful sync" do
      allow(presenter).to receive(:last_successful_sync).and_return(nil)

      expect(presenter.for_point(latitude: 44.0, longitude: -121.0)[:status]).to eq(:stale)
    end
  end

  describe "#map_features when fresh" do
    before do
      allow(presenter).to receive(:last_successful_sync).and_return(fresh_sync)
      allow(presenter).to receive(:active_incidents).and_return([perimeter_fire, near_fire])
    end

    it "emits perimeter and point features with NIFC attribution and as-of" do
      features = presenter.map_features(latitude: 44.0, longitude: -121.0)
      kinds = features.map { |feature| feature.dig(:properties, :kind) }

      expect(kinds).to include("wildfire", "wildfire_incident")
      expect(features.map { |feature| feature.dig(:properties, :data_attribution) }.uniq).to eq(["NIFC/WFIGS"])
      expect(features.map { |feature| feature.dig(:properties, :as_of) }.uniq).to eq([(now - 3600).iso8601])

      perimeter_feature = features.find { |feature| feature.dig(:properties, :kind) == "wildfire" }
      expect(perimeter_feature.dig(:geometry, "type")).to eq("Polygon")
      point_feature = features.find { |feature| feature.dig(:properties, :kind) == "wildfire_incident" }
      expect(point_feature.dig(:geometry, "type")).to eq("Point")
    end
  end

  def deg_per_mile
    1609.344 / 6_378_137.0 * 180 / Math::PI
  end
end
