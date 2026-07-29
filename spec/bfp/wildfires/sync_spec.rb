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
  let(:inciweb_body) { File.read(fixture_path("inciweb.xml")) }
  let(:cedar_irwin) { "A1B2C3D4-1111-2222-3333-444455556666" }
  let(:cedar_information_url) { "https://inciweb.wildfire.gov/incident-information/ordef-cedar-creek-fire" }

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

  it "persists a matched InciWeb information_url and records a link count" do
    run_sync(points_body, perimeters_body)

    cedar = BFP::Wildfires::WildfireIncident.first(irwin_id: cedar_irwin)
    expect(cedar.information_url).to eq(cedar_information_url)

    sync = BFP::Wildfires::WildfireSync.last_successful
    expect(sync.metadata_json.to_hash["information_urls"]).to eq(2)
    expect(sync.metadata_json.to_hash).not_to have_key("inciweb_error")
  end

  it "preserves an existing information_url when a later run has no matching RSS entry" do
    run_sync(points_body, perimeters_body)
    cedar = BFP::Wildfires::WildfireIncident.first(irwin_id: cedar_irwin)
    expect(cedar.information_url).to eq(cedar_information_url)

    counts = run_sync(points_body, perimeters_body, empty_inciweb_body)

    expect(counts[:success]).to be(true)
    cedar.refresh
    expect(cedar.information_url).to eq(cedar_information_url)
  end

  it "still succeeds and records the error class when the InciWeb fetch raises" do
    sync = BFP::Wildfires::Sync.new
    allow(sync).to receive(:get).with(BFP::Wildfires::Feed.points_query_url)
      .and_return(BFP::Wildfires::Sync::Response.new("200", points_body))
    allow(sync).to receive(:get).with(BFP::Wildfires::Feed.perimeters_query_url)
      .and_return(BFP::Wildfires::Sync::Response.new("200", perimeters_body))
    allow(sync).to receive(:get).with(BFP::Wildfires::Feed::INCIWEB_RSS_URL)
      .and_raise(RuntimeError.new("rss down"))

    counts = sync.run

    expect(counts[:success]).to be(true)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
    expect(BFP::Wildfires::WildfireIncident.first(irwin_id: cedar_irwin).information_url).to be_nil
    sync_row = BFP::Wildfires::WildfireSync.last_successful
    expect(sync_row.metadata_json.to_hash["inciweb_error"]).to eq("RuntimeError")
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

  it "fails the run when the points feed returns an ArcGIS error payload with HTTP 200" do
    run_sync(points_body, perimeters_body)

    error_body = JSON.generate({"error" => {"code" => 400, "message" => "Error performing query"}})
    counts = run_sync(error_body, perimeters_body)

    expect(counts[:success]).to be(false)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
  end

  # The July 2026 outage: the perimeters response outgrew the body cap, every
  # sync failed for days, and the staleness TTL then hid every fire sitewide.
  # Perimeters are enrichment, so their failure must not cost us the fire set.
  it "still publishes the incident set when the perimeters feed keeps failing" do
    run_sync(points_body, perimeters_body)
    cedar = BFP::Wildfires::WildfireIncident.first(irwin_id: cedar_irwin)
    original_bounds = [cedar.min_lon, cedar.min_lat, cedar.max_lon, cedar.max_lat]

    sync = build_sync(perimeters: ->(_url) { raise "Response exceeded 8388608 bytes" })
    counts = sync.run

    expect(counts[:success]).to be(true)
    expect(counts[:incidents]).to eq(3)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)

    cedar.refresh
    expect(cedar.perimeter_geometry).to include("type" => "Polygon")
    expect([cedar.min_lon, cedar.min_lat, cedar.max_lon, cedar.max_lat]).to eq(original_bounds)

    sync_row = BFP::Wildfires::WildfireSync.last_successful
    expect(sync_row.metadata_json.to_hash["perimeters_error"]).to eq("RuntimeError")
    expect(sync_row.metadata_json.to_hash["perimeters_error_message"]).to match(/exceeded/)
  end

  it "keeps a run healthy when an unusable perimeters payload arrives with HTTP 200" do
    counts = run_sync(points_body, JSON.generate({"error" => {"code" => 400, "message" => "Error performing query"}}))

    expect(counts[:success]).to be(true)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
    expect(BFP::Wildfires::WildfireSync.last_successful.metadata_json.to_hash["perimeters_error"])
      .to eq("BFP::Wildfires::Feed::FeedError")
  end

  it "retries a throttled ArcGIS page instead of losing the whole cycle" do
    calls = 0
    throttle_once = lambda do |_url|
      calls += 1
      (calls == 1) ? throttled_body : points_body
    end

    counts = build_sync(points: throttle_once).run

    expect(calls).to eq(2)
    expect(counts).to include(success: true, incidents: 3)
  end

  it "pages a truncated feed until ArcGIS stops reporting more records" do
    counts = build_sync(points: ->(url) { page_body(points_body, URI.decode_www_form(URI(url).query).to_h["resultOffset"].to_i) }).run

    expect(counts).to include(success: true, incidents: 3)
    expect(BFP::Wildfires::WildfireIncident.where(active: true).count).to eq(3)
  end

  it "records a failure row without raising when a feed request fails" do
    sync = BFP::Wildfires::Sync.new(retry_backoff_seconds: 0)
    allow(sync).to receive(:get).and_raise(RuntimeError.new("boom"))

    counts = sync.run

    expect(counts[:success]).to be(false)
    latest = BFP::Wildfires::WildfireSync.reverse(:id).first
    expect(latest.success).to be(false)
    expect(latest.error_message).to eq("boom")
    expect(latest.error_class).to eq("RuntimeError")
  end

  def run_sync(points, perimeters, inciweb = inciweb_body)
    build_sync(points: points, perimeters: perimeters, inciweb: inciweb).run
  end

  # Stubs by URL rather than call order so paging and retries (which change how
  # many requests a run makes) do not shift which body a call receives. A body
  # may be a callable, which is invoked per request for retry scenarios.
  def build_sync(points: points_body, perimeters: perimeters_body, inciweb: inciweb_body)
    sync = BFP::Wildfires::Sync.new(retry_backoff_seconds: 0)
    allow(sync).to receive(:get) do |url|
      body = case url
      when /WFIGS_Incident_Locations_Current/ then points
      when /WFIGS_Interagency_Perimeters_Current/ then perimeters
      else inciweb
      end
      body = body.call(url) if body.respond_to?(:call)
      BFP::Wildfires::Sync::Response.new("200", body)
    end
    sync
  end

  def throttled_body
    JSON.generate({"error" => {"code" => 429, "message" => "Unable to perform query. Too many requests."}})
  end

  def page_body(body, offset)
    payload = JSON.parse(body)
    features = payload["features"]
    payload["features"] = (offset.zero? ? features.first(1) : features.drop(1))
    payload["properties"] = {"exceededTransferLimit" => true} if offset.zero?
    JSON.generate(payload)
  end

  def empty_inciweb_body
    %(<?xml version="1.0"?><rss version="2.0"><channel><title>InciWeb</title></channel></rss>)
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
