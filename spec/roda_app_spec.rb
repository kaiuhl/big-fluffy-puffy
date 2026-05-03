require "json"
require_relative "spec_helper"
require_relative "../server/roda_app"

RSpec.describe RodaApp do
  include Rack::Test::Methods

  def app
    described_class.app
  end

  it "responds to health checks" do
    get "/health"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to eq("status" => "ok")
  end

  it "exposes a minimal version endpoint" do
    get "/api/version"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include(
      "app" => "big-fluffy-puffy",
      "env" => "test"
    )
  end

  it "exposes the fire restriction forests endpoint" do
    get "/api/fire-restrictions/forests"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include("forests")
  end

  it "serves the fire restrictions page shell" do
    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("National Forest Fire Restrictions")
    expect(last_response.body).to include('href="/"')
    expect(last_response.body).to include('aria-current="page">Fire Restrictions')
  end

  it "renders grouped fire restriction sections" do
    stub_fire_restriction_records(
      [
        restriction_record(name: "Restriction Forest", status: "stage_1", campfire_policy: "developed_sites_only", review_status: "accepted"),
        restriction_record(name: "Clear Forest", status: "none", campfire_policy: "allowed", review_status: "auto_accepted"),
        restriction_record(name: "Review Forest", status: "unknown", campfire_policy: "unknown", review_status: "needs_review")
      ]
    )

    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Active Restrictions")
    expect(last_response.body).to include("No Published Restrictions")
    expect(last_response.body).to include("Needs Review / Unknown")
    expect(last_response.body).to include("Restriction Forest")
    expect(last_response.body).to include("Clear Forest")
    expect(last_response.body).to include("Review Forest")
    expect(last_response.body).to include("Stage 1")
    expect(last_response.body).to include("Needs Review")
  end

  it "renders source links and updated timestamps on the fire restrictions page" do
    stub_fire_restriction_records(
      [
        restriction_record(
          name: "Source Forest",
          status: "none",
          source_url: "https://example.test/current-order",
          source_title: "Current fire order",
          last_checked_at: "2026-05-03T05:25:08Z"
        )
      ]
    )

    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("https://example.test/current-order")
    expect(last_response.body).to include("Current fire order")
    expect(last_response.body).to include("2026-05-03T05:25:08Z")
  end

  it "renders a celebratory message when no forests have active published restrictions" do
    stub_fire_restriction_records(
      [
        restriction_record(name: "Clear Forest", status: "none", review_status: "auto_accepted"),
        restriction_record(name: "Review Forest", status: "unknown", review_status: "needs_review")
      ]
    )

    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("No published forest-wide restrictions right now.")
  end

  it "serves the initial landing page" do
    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Big Fluffy Puffy")
    expect(last_response.body).to include("Skip the campfire. Pack the warmth.")
    expect(last_response.body).to include("nonprofit building fireless camp culture")
    expect(last_response.body).to include('href="/fire-restrictions"')
  end

  it "responds to head requests for the landing page" do
    head "/"

    expect(last_response).to be_ok
    expect(last_response.body).to be_empty
  end

  it "serves public stylesheets" do
    get "/styles/site.css"

    expect(last_response).to be_ok
    expect(last_response.body).to include("--signal: #ff4b1f")
  end

  def stub_fire_restriction_records(records)
    allow_any_instance_of(described_class).to receive(:fire_restriction_records).and_return(records)
  end

  def restriction_record(overrides = {})
    {
      slug: "example",
      name: "Example Forest",
      unit_type: "national_forest",
      market_bucket: "oregon",
      region_code: "R6",
      status: "none",
      campfire_policy: "allowed",
      fire_danger_rating: nil,
      ifpl_level: nil,
      confidence: 0.9,
      review_status: "auto_accepted",
      effective_start: nil,
      effective_end: nil,
      order_number: nil,
      affected_area: nil,
      summary: "No restrictions are published.",
      evidence_quotes: [],
      last_checked_at: "2026-05-03T05:00:00Z",
      source_url: nil,
      source_title: nil,
      sources: [
        {
          slug: "example-fire-info",
          name: "Fire Information",
          source_type: "fs_fire_info_page",
          authority: "usfs",
          url: "https://example.test/fire/info",
          last_checked_at: "2026-05-03T04:00:00Z"
        }
      ]
    }.merge(overrides)
  end
end
