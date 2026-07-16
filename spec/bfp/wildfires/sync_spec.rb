require "json"
require_relative "../../../config/boot"
require_relative "../../spec_helper"

RSpec.describe "BFP::Wildfires::Sync", :db do
  before do
    skip "Set RUN_DB_SPECS=true with TEST_DATABASE_URL to run database integration specs." unless ENV["RUN_DB_SPECS"] == "true"
    prepare_wildfire_database
  end

  let(:points_body) { File.read(fixture_path("points.geojson")) }
  let(:perimeters_body) { File.read(fixture_path("perimeters.geojson")) }

  it "upserts incidents and records a successful sync" do
    counts = run_sync(points_body, perimeters_body)

    expect(counts).to include(success: true, incidents: 3, perimeters: 1, deactivated: 0)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)

    cedar = BFP::Wildfires::WildfireIncident.first(irwin_id: "A1B2C3D4-1111-2222-3333-444455556666")
    expect(cedar.perimeter_geometry).to include("type" => "Polygon")
    expect(cedar.acres).to eq(12500.75)

    sync = BFP::Wildfires::WildfireSync.last_successful
    expect(sync.success).to be(true)
    expect(sync.incident_count).to eq(3)
    expect(sync.perimeter_count).to eq(1)
  end

  it "deactivates incidents missing from a later run and preserves first_seen_at" do
    run_sync(points_body, perimeters_body)
    original = BFP::Wildfires::WildfireIncident.first(irwin_id: "A1B2C3D4-1111-2222-3333-444455556666")
    first_seen = original.first_seen_at

    counts = run_sync(single_point_body, perimeters_body)

    expect(counts).to include(incidents: 1, deactivated: 2)
    original.refresh
    expect(original.active).to be(true)
    expect(original.first_seen_at.to_i).to eq(first_seen.to_i)
    expect(BFP::Wildfires::WildfireIncident.where(active: false).count).to eq(2)
  end

  it "keeps the last known perimeter when a later run has none for an active fire" do
    run_sync(points_body, perimeters_body)
    cedar = BFP::Wildfires::WildfireIncident.first(irwin_id: "A1B2C3D4-1111-2222-3333-444455556666")
    expect(cedar.perimeter_geometry).to include("type" => "Polygon")
    original_bounds = [cedar.min_lon, cedar.min_lat, cedar.max_lon, cedar.max_lat]

    counts = run_sync(points_body, empty_perimeters_body)

    expect(counts).to include(success: true, incidents: 3)
    cedar.refresh
    expect(cedar.perimeter_geometry).to include("type" => "Polygon")
    expect([cedar.min_lon, cedar.min_lat, cedar.max_lon, cedar.max_lat]).to eq(original_bounds)
  end

  it "fails the run instead of deactivating everything when the points feed is empty" do
    run_sync(points_body, perimeters_body)

    counts = run_sync(empty_points_body, perimeters_body)

    expect(counts[:success]).to be(false)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
    latest = BFP::Wildfires::WildfireSync.reverse(:id).first
    expect(latest.success).to be(false)
    expect(latest.error_class).to eq("BFP::Wildfires::Feed::FeedError")
  end

  it "fails the run when a feed returns an ArcGIS error payload with HTTP 200" do
    run_sync(points_body, perimeters_body)

    error_body = JSON.generate({"error" => {"code" => 500, "message" => "Error performing query"}})
    counts = run_sync(points_body, error_body)

    expect(counts[:success]).to be(false)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
  end

  it "records a failure row without raising when a feed request fails" do
    sync = BFP::Wildfires::Sync.new
    allow(sync).to receive(:get).and_raise(RuntimeError.new("boom"))

    counts = sync.run

    expect(counts[:success]).to be(false)
    latest = BFP::Wildfires::WildfireSync.reverse(:id).first
    expect(latest.success).to be(false)
    expect(latest.error_message).to eq("boom")
    expect(latest.error_class).to eq("RuntimeError")
  end

  def run_sync(points, perimeters)
    sync = BFP::Wildfires::Sync.new
    allow(sync).to receive(:get).and_return(
      BFP::Wildfires::Sync::Response.new("200", points),
      BFP::Wildfires::Sync::Response.new("200", perimeters)
    )
    sync.run
  end

  def single_point_body
    payload = JSON.parse(points_body)
    payload["features"] = payload["features"].select { |feature| feature.dig("properties", "IncidentName") == "Cedar Creek" }
    JSON.generate(payload)
  end

  def empty_points_body
    JSON.generate({"type" => "FeatureCollection", "features" => []})
  end

  def empty_perimeters_body
    JSON.generate({"type" => "FeatureCollection", "features" => []})
  end

  def prepare_wildfire_database
    require "sequel/extensions/migration"

    Sequel::Migrator.run(BFP.db, File.join(BFP.root, "db/migrations"))
    require "bfp/wildfires"
    BFP.db.run("TRUNCATE wildfire_incidents, wildfire_syncs RESTART IDENTITY")
  end

  def fixture_path(name)
    File.join(BFP.root, "spec/fixtures/wildfires", name)
  end
end
