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
    expect(last_response.body).to include("PNW Fire Restrictions")
    expect(last_response.body).to include('href="/"')
    expect(last_response.body).to include('aria-current="page">Fire Restrictions')
    expect(last_response.body).to include('href="/vendor/leaflet/leaflet.css"')
    expect(last_response.body).to include('src="/vendor/leaflet/leaflet.js"')
    expect(last_response.body).to include('src="/scripts/fire-restrictions.js"')
  end

  it "exposes a GeoJSON fire restriction map endpoint" do
    stub_fire_restriction_records(
      [
        restriction_record(slug: "deschutes", name: "Restriction Forest", status: "stage_1", campfire_policy: "developed_sites_only", review_status: "accepted", climate_low_context: climate_context),
        restriction_record(slug: "colville", name: "Clear Forest", status: "none", campfire_policy: "unknown", review_status: "auto_accepted", last_checked_at: "2026-05-03T06:00:05Z"),
        restriction_record(slug: "modoc", name: "Review Forest", status: "unknown", campfire_policy: "unknown", review_status: "needs_review")
      ]
    )

    get "/api/fire-restrictions/map"

    expect(last_response).to be_ok
    expect(last_response.content_type).to include("application/geo+json")

    data = JSON.parse(last_response.body)
    features_by_slug = data.fetch("features").to_h { |feature| [feature.dig("properties", "slug"), feature] }

    expect(data.fetch("type")).to eq("FeatureCollection")
    expect(features_by_slug.keys).to match_array(%w[colville deschutes modoc])
    expect(features_by_slug.fetch("deschutes").dig("properties", "map_status")).to eq("active")
    expect(features_by_slug.fetch("colville").dig("properties", "map_status")).to eq("none")
    expect(features_by_slug.fetch("colville").dig("properties", "campfire_policy")).to eq("allowed")
    expect(features_by_slug.fetch("colville").dig("properties", "last_checked_label")).to eq("May 3, 2026")
    expect(features_by_slug.fetch("modoc").dig("properties", "map_status")).to eq("unknown")
    expect(features_by_slug.fetch("deschutes").dig("properties", "climate_low_context", "month_name")).to eq("May")
    expect(features_by_slug.fetch("deschutes").fetch("geometry")).to include("type", "coordinates")
  end

  it "renders grouped fire restriction sections" do
    stub_fire_restriction_records(
      [
        restriction_record(slug: "deschutes", name: "Restriction Forest", status: "stage_1", campfire_policy: "developed_sites_only", review_status: "accepted", climate_low_context: climate_context),
        restriction_record(slug: "colville", name: "Clear Forest", status: "none", campfire_policy: "unknown", review_status: "auto_accepted"),
        restriction_record(slug: "modoc", name: "Review Forest", status: "unknown", campfire_policy: "unknown", review_status: "needs_review")
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
    expect(last_response.body).to include("Developed Sites Only")
    expect(last_response.body).to include("<th scope=\"col\">Typical May lows</th>")
    expect(last_response.body).to include('class="climate-low-sparkline"')
    expect(last_response.body).not_to include("Average May lows</text>")
    expect(last_response.body).to include("Average May overnight lows by elevation: 3K 42 degrees Fahrenheit, 5K 40 degrees Fahrenheit, 7K 33 degrees Fahrenheit")
    expect(last_response.body).to include('class="climate-low-dot"')
    expect(last_response.body).to include("Allowed")
    expect(last_response.body).to include("Needs Review")
    expect(last_response.body).to include('id="restrictions-map"')
    expect(last_response.body).to include('data-map-endpoint="/api/fire-restrictions/map"')
    expect(last_response.body).to include("Forest Status Map")
    expect(last_response.body).not_to include("<th scope=\"col\">Status</th>")
    expect(last_response.body).to include('for="restrictions-search"')
    expect(last_response.body).to include('id="restrictions-filter-status"')
    expect(last_response.body).to include('data-label="Campfires"')
    expect(last_response.body).to include('data-label="Typical May lows"')
    expect(last_response.body).to include('data-label="Source"')
    expect(last_response.body).to include('data-label="Checked"')
    expect(last_response.body).to include('data-label="Note"')
    expect(last_response.body).to include("restrictions-filter-empty")
  end

  it "renders region and state under the forest name and sorts by state then forest" do
    stub_fire_restriction_records(
      [
        restriction_record(slug: "colville", name: "Colville National Forest", region_code: "R06"),
        restriction_record(slug: "modoc", name: "Modoc National Forest", region_code: "R05"),
        restriction_record(slug: "deschutes", name: "Deschutes National Forest", region_code: "R06")
      ]
    )

    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).not_to include("<th scope=\"col\">State</th>")
    expect(last_response.body).to include("<small>R06 / Oregon</small>")
    expect(last_response.body).to include("<small>R06 / Washington</small>")
    expect(last_response.body).to include("<small>R05 / California</small>")
    expect(last_response.body).not_to include("restrictions-state-row")
    expect(last_response.body.index("Deschutes National Forest")).to be < last_response.body.index("Colville National Forest")
    expect(last_response.body.index("Colville National Forest")).to be < last_response.body.index("Modoc National Forest")
  end

  it "renders source links and relative checked labels on the fire restrictions page" do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 3, 6, 0, 0))

    stub_fire_restriction_records(
      [
        restriction_record(
          name: "Source Forest",
          status: "none",
          source_url: "https://example.test/current-order",
          source_title: "Current fire order",
          last_checked_at: "2026-05-03T05:25:08Z"
        ),
        restriction_record(
          name: "Week Old Forest",
          status: "none",
          last_checked_at: "2026-04-26T06:00:00Z"
        )
      ]
    )

    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("https://example.test/current-order")
    expect(last_response.body).to include("Current fire order")
    expect(last_response.body).to include(">May 3, 2026</time>")
    expect(last_response.body).to include(">Apr 26, 2026</time>")
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

  it "serves the fire restrictions search script" do
    get "/scripts/fire-restrictions.js"

    expect(last_response).to be_ok
    expect(last_response.body).to include("setupFireRestrictionSearch")
    expect(last_response.body).to include("dataset.filterText")
    expect(last_response.body).to include("timeZone: \"UTC\"")
    expect(last_response.body).to include("last_checked_label")
    expect(last_response.body).to include("climate_low_context")
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
      climate_low_context: nil,
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

  def climate_context
    {
      month: 5,
      month_name: "May",
      dataset_slug: "prism-1991-2020-tmin-800m",
      source_label: "PRISM 1991-2020 normals",
      source_url: "https://prism.oregonstate.edu/normals/",
      bands: [
        {
          label: "2,000-4,000 ft",
          elevation_min_ft: 2000,
          elevation_max_ft: 4000,
          mean_low_f: 42.1,
          cold_p10_low_f: 39.8,
          warm_p90_low_f: 44.9,
          sample_cell_count: 40,
          area_pct_of_forest: 12.0
        },
        {
          label: "4,000-6,000 ft",
          elevation_min_ft: 4000,
          elevation_max_ft: 6000,
          mean_low_f: 39.7,
          cold_p10_low_f: 35.1,
          warm_p90_low_f: 44.2,
          sample_cell_count: 12,
          area_pct_of_forest: 4.2
        },
        {
          label: "6,000-8,000 ft",
          elevation_min_ft: 6000,
          elevation_max_ft: 8000,
          mean_low_f: 33.2,
          cold_p10_low_f: 29.8,
          warm_p90_low_f: 36.7,
          sample_cell_count: 16,
          area_pct_of_forest: 5.4
        }
      ]
    }
  end
end
