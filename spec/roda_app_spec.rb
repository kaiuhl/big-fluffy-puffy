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

  it "exposes the canonical fire restriction land-units endpoint" do
    get "/api/fire-restrictions/land-units"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include("land_units")
  end

  it "exposes place search suggestions" do
    allow_any_instance_of(described_class).to receive(:place_search_suggestions).with("Burnt", limit: 8).and_return(
      [
        {
          slug: "burnt-lake",
          name: "Burnt Lake",
          place_type: "lake",
          subtitle: "Lake / Mt. Hood National Forest / Oregon",
          latitude: 45.35,
          longitude: -121.8,
          matched_land_units: [{slug: "mt-hood", name: "Mt. Hood National Forest"}],
          matched_rule_count: 1,
          url: "/trip-check/burnt-lake"
        }
      ]
    )

    get "/api/places/search?q=Burnt"

    expect(last_response).to be_ok
    data = JSON.parse(last_response.body)
    expect(data.dig("places", 0, "name")).to eq("Burnt Lake")
    expect(data.dig("places", 0, "url")).to eq("/trip-check/burnt-lake")
  end

  it "serves the fire restrictions page shell" do
    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("PNW Fire Restrictions")
    expect(last_response.body).to include('href="/"')
    expect(last_response.body).to include('aria-current="page">Fire Restrictions')
    expect(last_response.body).to include('href="/vendor/leaflet/leaflet.css"')
    expect(last_response.body).to include('href="/styles/site.css?v=20260517-trip-check-page-9"')
    expect(last_response.body).to include('src="/vendor/leaflet/leaflet.js"')
    expect(last_response.body).to include('src="/scripts/fire-restrictions.js?v=20260517-trip-check-page-3"')
    expect(last_response.body).to include("Source-linked, not official")
    expect(last_response.body).to include("Big Fluffy Puffy is not a government agency")
    expect(last_response.body).to include("Unknown means BFP has not published a claim yet")
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
    expect(last_response.body).to include('href="/fire-restrictions/deschutes"')
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
    expect(last_response.body).to include('data-map-basemap="osm"')
    expect(last_response.body).to include('data-map-endpoint="/api/fire-restrictions/map"')
    expect(last_response.body).to include("Area Status Map")
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

  it "serves per-forest fire restriction detail pages" do
    stub_fire_restriction_detail("deschutes", forest_detail)

    get "/fire-restrictions/deschutes"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Deschutes National Forest")
    expect(last_response.body).not_to include("Area-wide status")
    expect(last_response.body).to include('class="forest-summary-layout"')
    expect(last_response.body).to include('class="forest-summary-item forest-summary-item-climate"')
    expect(last_response.body).not_to include("<span>Campfires</span>")
    expect(last_response.body).to include("<strong>Campfires only in developed sites.</strong>")
    expect(last_response.body).to include("Seasonal / Current Orders")
    expect(last_response.body).to include("Permanent / Standing Rules")
    expect(last_response.body).to include("Jefferson Park")
    expect(last_response.body).to include("<th scope=\"col\">Fire Use</th>")
    expect(last_response.body).not_to include("<th scope=\"col\">Map</th>")
    expect(last_response.body).to include('data-label="Fire Use"')
    expect(last_response.body).not_to include('data-label="Map"')
    expect(last_response.body).to include('class="fire-use-sparkline"')
    expect(last_response.body).not_to include('class="fire-use-summary"')
    expect(last_response.body).to include('title="Campfires prohibited. Gas stoves allowed with shutoff valve. Alcohol stoves, charcoal, solid fuel stoves, and wood stoves prohibited."')
    expect(last_response.body).to include("Gas")
    expect(last_response.body).to include("allowed with shutoff valve")
    expect(last_response.body).not_to include("Stoves / Charcoal")
    expect(last_response.body).to include('data-map-endpoint="/api/fire-restrictions/land-units/deschutes/map"')
    expect(last_response.body).to include('data-map-fit-zoom-offset="1"')
    expect(last_response.body).to include('data-map-status-mode="localized-restrictions"')
    expect(last_response.body).to include('data-map-total-restrictions="2"')
  end

  it "returns 404 for unknown per-forest pages" do
    stub_fire_restriction_detail("unknown", nil)

    get "/fire-restrictions/unknown"

    expect(last_response.status).to eq(404)
    expect(last_response.body).to include("Area Not Found")
  end

  it "serves per-forest fire restriction detail JSON" do
    stub_fire_restriction_detail("deschutes", forest_detail)

    get "/api/fire-restrictions/forests/deschutes"

    expect(last_response).to be_ok
    data = JSON.parse(last_response.body)

    expect(data.dig("forest", "slug")).to eq("deschutes")
    expect(data.dig("land_unit", "slug")).to eq("deschutes")
    expect(data.fetch("localized_restrictions").first).to include(
      "title" => "Jefferson Park",
      "duration_type" => "permanent"
    )
  end

  it "serves canonical land-unit fire restriction detail JSON" do
    stub_fire_restriction_detail("deschutes", forest_detail)

    get "/api/fire-restrictions/land-units/deschutes"

    expect(last_response).to be_ok
    data = JSON.parse(last_response.body)

    expect(data.dig("land_unit", "slug")).to eq("deschutes")
    expect(data.fetch("map_endpoint")).to eq("/api/fire-restrictions/land-units/deschutes/map")
  end

  it "serves per-forest fire restriction map GeoJSON" do
    allow_any_instance_of(described_class).to receive(:forest_fire_restriction_map).with("deschutes").and_return(
      {
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: {"type" => "Polygon", "coordinates" => []},
            properties: {kind: "localized_restriction", name: "Jefferson Park"}
          }
        ]
      }
    )

    get "/api/fire-restrictions/forests/deschutes/map"

    expect(last_response).to be_ok
    expect(last_response.content_type).to include("application/geo+json")
    expect(JSON.parse(last_response.body).dig("features", 0, "properties", "kind")).to eq("localized_restriction")
  end

  it "serves canonical per-land-unit fire restriction map GeoJSON" do
    allow_any_instance_of(described_class).to receive(:land_unit_fire_restriction_map).with("deschutes").and_return(
      {
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: {"type" => "Polygon", "coordinates" => []},
            properties: {kind: "localized_restriction", name: "Jefferson Park"}
          }
        ]
      }
    )

    get "/api/fire-restrictions/land-units/deschutes/map"

    expect(last_response).to be_ok
    expect(last_response.content_type).to include("application/geo+json")
    expect(JSON.parse(last_response.body).dig("features", 0, "properties", "kind")).to eq("localized_restriction")
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
    expect(last_response.body).to include("<small>USFS National Forest / R06 / Oregon</small>")
    expect(last_response.body).to include("<small>USFS National Forest / R06 / Washington</small>")
    expect(last_response.body).to include("<small>USFS National Forest / R05 / California</small>")
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
    expect(last_response.body).to include("No published area-wide restrictions right now.")
  end

  it "serves the initial landing page" do
    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Big Fluffy Puffy")
    expect(last_response.body).to include("Skip the campfire. Pack the warmth.")
    expect(last_response.body).to include("nonprofit building fireless camp culture")
    expect(last_response.body).to include('href="/fire-restrictions"')
    expect(last_response.body).to include('href="/why-fireless"')
    expect(last_response.body).to include('href="/about"')
    expect(last_response.body).to include('href="/contact"')
    expect(last_response.body).to include('class="site-brand site-brand-active" href="/" aria-current="page"')
    expect(last_response.body).to include('action="/trip-check"')
    expect(last_response.body).to include("Where are you going?")
    expect(last_response.body).to include('src="/scripts/place-search.js?v=20260517-trip-check"')
    expect(last_response.body).not_to include(">Home</a>")
  end

  it "renders trip check search disambiguation" do
    allow_any_instance_of(described_class).to receive(:trip_check_search_results).with("lake", limit: 8).and_return(
      [
        {
          slug: "burnt-lake",
          name: "Burnt Lake",
          place_type: "lake",
          subtitle: "Lake / Mt. Hood National Forest / Oregon",
          matched_rule_count: 1,
          url: "/trip-check/burnt-lake"
        },
        {
          slug: "wahtum-lake",
          name: "Wahtum Lake",
          place_type: "lake",
          subtitle: "Lake / Mt. Hood National Forest / Oregon",
          matched_rule_count: 1,
          url: "/trip-check/wahtum-lake"
        }
      ]
    )

    get "/trip-check?q=lake"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Trip Check Search")
    expect(last_response.body).to include("Burnt Lake")
    expect(last_response.body).to include("Wahtum Lake")
    expect(last_response.body).to include('href="/trip-check/burnt-lake"')
  end

  it "renders a trip check page" do
    allow_any_instance_of(described_class).to receive(:trip_check_detail).with("burnt-lake").and_return(trip_check_payload)

    get "/trip-check/burnt-lake"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Burnt Lake Trip Check")
    expect(last_response.body).to include("In <a href=\"/fire-restrictions/mt-hood\">Mt. Hood National Forest</a>")
    expect(last_response.body).not_to include('<p class="summary-kicker">Trip check answer</p>')
    expect(last_response.body).to include("No campfires.")
    expect(last_response.body).to include("A local fire-use rule applies to Burnt Lake.")
    expect(last_response.body).to include("Area-wide campfires")
    expect(last_response.body).to include("<dd>Allowed</dd>")
    expect(last_response.body).to include("Localized match")
    expect(last_response.body).to include("1 rule")
    expect(last_response.body).to include("Localized Rules At This Waypoint")
    expect(last_response.body).to include("See all localized rules in Mt. Hood National Forest")
    expect(last_response.body).to include("Source-linked, not official")
    expect(last_response.body).to include("Place data:")
    expect(last_response.body).to include('data-map-endpoint="/api/trip-check/burnt-lake/map"')
    expect(last_response.body).to include('data-map-focus-lat="45.35"')
    expect(last_response.body).to include('data-map-focus-zoom="10"')
    expect(last_response.body).to include('data-map-total-restrictions="2"')
    expect(last_response.body).to include('src="/scripts/fire-restrictions.js?v=20260517-trip-check-page-3"')
  end

  it "serves trip check map GeoJSON" do
    allow_any_instance_of(described_class).to receive(:trip_check_map).with("burnt-lake").and_return(
      {
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: {type: "Point", coordinates: [-121.8, 45.35]},
            properties: {kind: "trip_check_place", name: "Burnt Lake"}
          }
        ]
      }
    )

    get "/api/trip-check/burnt-lake/map"

    expect(last_response).to be_ok
    expect(last_response.content_type).to include("application/geo+json")
    expect(JSON.parse(last_response.body).dig("features", 0, "properties", "name")).to eq("Burnt Lake")
  end

  it "serves simple public identity pages" do
    pages = {
      "/about" => ["Started by people who still love campfires", "aria-current=\"page\">About"],
      "/why-fireless" => ["The fire can&#39;t be the plan", "aria-current=\"page\">Why Fireless"],
      "/contact" => ["Say hello", "aria-current=\"page\">Contact"]
    }

    pages.each do |path, expected_text|
      get path

      expect(last_response).to be_ok
      expect(last_response.body).to include(*expected_text)
      expect(last_response.body).to include('href="/fire-restrictions"')
      expect(last_response.body).to include("<meta property=\"og:title\"")
    end

    get "/about"

    expect(last_response.body).to include("What We Are Building")
    expect(last_response.body).to include("Join us in protecting what remains of our unburned forests")
    expect(last_response.body).to include("Big Fluffy Puffy began as a nudge to friends")

    get "/contact"

    expect(last_response.body).to include('<a href="mailto:hello@puffy.camp">hello@puffy.camp</a>')
    expect(last_response.body).to include('href="mailto:hello@puffy.camp"')
    expect(last_response.body).to include('<a href="/fire-restrictions">Review the current fire restriction monitor.</a>')
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
    expect(last_response.body).to include("--restrictions-section-title-size")
    expect(last_response.body).to include(".restrictions-map-expanded")
    expect(last_response.body).to include(".restrictions-map-size-button")
    expect(last_response.body).to include(".trip-check-waypoint-icon")
    expect(last_response.body).to include(".map-popup-place")
    expect(last_response.body).to include(".map-popup-place-forest")
    expect(last_response.body).to include(".map-popup-place-meta")
    expect(last_response.body).to include("transition: height 160ms ease")
    expect(last_response.body).to include("stroke-width: 2.5")
  end

  it "serves the fire restrictions search script" do
    get "/scripts/fire-restrictions.js"

    expect(last_response).to be_ok
    expect(last_response.body).to include("setupFireRestrictionSearch")
    expect(last_response.body).to include("dataset.filterText")
    expect(last_response.body).to include("timeZone: \"UTC\"")
    expect(last_response.body).to include("last_checked_label")
    expect(last_response.body).to include("tile.openstreetmap.org/{z}/{x}/{y}.png")
    expect(last_response.body).to include("OpenStreetMap")
    expect(last_response.body).to include("USGSTopo/MapServer/tile/{z}/{y}/{x}")
    expect(last_response.body).to include("USGS The National Map")
    expect(last_response.body).to include("DEFAULT_FIT_MAX_ZOOM = 8")
    expect(last_response.body).to include("animate: false")
    expect(last_response.body).to include("container.dataset.mapFitZoomOffset")
    expect(last_response.body).to include("focusMapOnWaypoint")
    expect(last_response.body).to include("container.dataset.mapFocusLat")
    expect(last_response.body).to include("fitZoomOffset")
    expect(last_response.body).to include("zoomMapAfterFit(map, zoomOffset)")
    expect(last_response.body).to include("currentZoom + zoomOffset")
    expect(last_response.body).to include("addOutsideBoundaryMask")
    expect(last_response.body).to include("if (!isBoundaryFeature(feature)) return holes")
    expect(last_response.body).to include("return !isBoundaryFeature(feature)")
    expect(last_response.body).to include("fillOpacity: 0.56")
    expect(last_response.body).to include("fillOpacity: 0.72")
    expect(last_response.body).to include("fillRule: \"nonzero\"")
    expect(last_response.body).to include("fillRule: \"evenodd\"")
    expect(last_response.body).to include("fillOpacity: 0.66")
    expect(last_response.body).to include("enableShapeDoubleClickZoom")
    expect(last_response.body).to include("addMapResizeControl")
    expect(last_response.body).to include("mapResizeIcon")
    expect(last_response.body).to include("mapStatusMessage")
    expect(last_response.body).to include("localizedRestrictionCount")
    expect(last_response.body).to include("uniqueLocalizedRestrictionCount")
    expect(last_response.body).to include("properties.rule_slug || properties.slug")
    expect(last_response.body).to include("properties.part_name")
    expect(last_response.body).to include("restriction_detail")
    expect(last_response.body).to include("geometry_basis")
    expect(last_response.body).to include("container.dataset.mapTotalRestrictions")
    expect(last_response.body).to include("restrictions-map-expanded")
    expect(last_response.body).to include("Expand map")
    expect(last_response.body).to include("Collapse map")
    expect(last_response.body).to include("refreshMapSize")
    expect(last_response.body).to include('container.addEventListener("dblclick"')
    expect(last_response.body).to include("zoomMapAround(map, map.mouseEventToLatLng(event), event)")
    expect(last_response.body).to include("shapeRepeatedClickZoomHandler")
    expect(last_response.body).to include("point.distanceTo(lastClick.point) < 12")
    expect(last_response.body).to include("isTripCheckPlaceFeature")
    expect(last_response.body).to include("tripCheckWaypointIcon")
    expect(last_response.body).to include("tripCheckPlacePopupContent")
    expect(last_response.body).to include("USGS quad")
    expect(last_response.body).to include("map-popup-place-forest")
    expect(last_response.body).to include("Boundary")
    expect(last_response.body).to include("Approximation shown on map. Read official sources and signs for exact boundaries.")
    expect(last_response.body).not_to include("DEFAULT_FIT_ZOOM_OFFSET")
    expect(last_response.body).not_to include("zoomInAfterFit")
    expect(last_response.body).not_to include("isUnknownFeature")
    expect(last_response.body).not_to include("isLocalizedRestrictionFeature")
    expect(last_response.body).not_to include("UNKNOWN_FILL_OPACITY")
    expect(last_response.body).not_to include("Geometry")
    expect(last_response.body).not_to include('color: isBoundary ? "#000000" : color')
    expect(last_response.body).not_to include("dashArray: isBoundary")
    expect(last_response.body).not_to include("climate_low_context")
  end

  it "serves the place search script" do
    get "/scripts/place-search.js"

    expect(last_response).to be_ok
    expect(last_response.body).to include("setupPlaceSearch")
    expect(last_response.body).to include("/api/places/search")
    expect(last_response.body).to include("data-place-search-results")
  end

  def stub_fire_restriction_records(records)
    allow_any_instance_of(described_class).to receive(:fire_restriction_records).and_return(records)
  end

  def stub_fire_restriction_detail(slug, detail)
    allow_any_instance_of(described_class).to receive(:forest_fire_restriction_detail).with(slug).and_return(detail)
    allow_any_instance_of(described_class).to receive(:land_unit_fire_restriction_detail).with(slug).and_return(detail)
  end

  def restriction_record(overrides = {})
    slug = overrides.fetch(:slug, "example")
    {
      slug: slug,
      name: "Example Forest",
      land_unit_url: "/fire-restrictions/#{slug}",
      forest_url: "/fire-restrictions/#{slug}",
      unit_type: "national_forest",
      agency: "USFS",
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

  def forest_detail
    record = restriction_record(
      slug: "deschutes",
      name: "Deschutes National Forest",
      forest_url: "/fire-restrictions/deschutes",
      land_unit_url: "/fire-restrictions/deschutes",
      status: "partial",
      campfire_policy: "developed_sites_only",
      review_status: "accepted",
      climate_low_context: climate_context
    )

    {
      land_unit: record,
      forest: record,
      map_endpoint: "/api/fire-restrictions/land-units/deschutes/map",
      legacy_map_endpoint: "/api/fire-restrictions/forests/deschutes/map",
      localized_restrictions: [
        {
          id: 12,
          slug: "jefferson-park",
          title: "Jefferson Park",
          status: "year_round",
          duration_type: "permanent",
          group: "permanent",
          campfire_policy: "prohibited",
          charcoal_policy: "prohibited",
          gas_stove_policy: "allowed_with_shutoff_valve",
          liquid_fuel_stove_policy: "allowed_with_shutoff_valve",
          alcohol_stove_policy: "prohibited",
          solid_fuel_stove_policy: "prohibited",
          wood_stove_policy: "prohibited",
          stove_shutoff_valve_required: true,
          affected_area: "Jefferson Park",
          summary: "Campfires are prohibited in Jefferson Park.",
          evidence_quotes: ["Campfires are prohibited"],
          source_url: "https://example.test/jefferson-park",
          source_title: "Jefferson Park rules",
          mapped: false,
          geometry_source_type: "none",
          season_start: nil,
          season_end: nil,
          effective_start: nil,
          effective_end: nil
        },
        {
          id: 13,
          slug: "temporary-order",
          title: "Temporary order",
          status: "stage_1",
          duration_type: "temporary",
          group: "current",
          campfire_policy: "developed_sites_only",
          charcoal_policy: "prohibited",
          gas_stove_policy: "allowed_with_shutoff_valve",
          liquid_fuel_stove_policy: "allowed_with_shutoff_valve",
          alcohol_stove_policy: "prohibited",
          solid_fuel_stove_policy: "prohibited",
          wood_stove_policy: "prohibited",
          stove_shutoff_valve_required: true,
          affected_area: "Dispersed campsites",
          source_url: "https://example.test/order",
          source_title: "Current order",
          mapped: true,
          geometry_source_type: "source_map",
          season_start: nil,
          season_end: nil,
          effective_start: "2026-07-01",
          effective_end: "2026-09-01"
        }
      ]
    }
  end

  def trip_check_payload
    {
      place: {
        slug: "burnt-lake",
        name: "Burnt Lake",
        place_type: "lake",
        latitude: 45.35,
        longitude: -121.8,
        state_code: "or",
        county_name: "Clackamas",
        map_name: "Bull Run Lake",
        source_url: "https://example.test/place"
      },
      verdict: {
        tone: "active",
        headline: "Campfires aren't allowed.",
        detail: "A local fire-use rule applies to Burnt Lake."
      },
      campfire_policy: "prohibited",
      fire_use: {
        campfire_policy: "prohibited",
        gas_stove_policy: "allowed_with_shutoff_valve",
        liquid_fuel_stove_policy: "allowed_with_shutoff_valve",
        alcohol_stove_policy: "unknown",
        charcoal_policy: "prohibited",
        solid_fuel_stove_policy: "prohibited",
        wood_stove_policy: "prohibited"
      },
      primary_forest: restriction_record(
        slug: "mt-hood",
        name: "Mt. Hood National Forest",
        forest_url: "/fire-restrictions/mt-hood",
        status: "none",
        campfire_policy: "allowed",
        source_url: "https://example.test/fire",
        source_title: "Fire information"
      ),
      matched_land_units: [
        {
          relationship: "contains_point",
          confidence: 0.98,
          forest: restriction_record(
            slug: "mt-hood",
            name: "Mt. Hood National Forest",
            forest_url: "/fire-restrictions/mt-hood",
            status: "none",
            campfire_policy: "allowed",
            source_url: "https://example.test/fire",
            source_title: "Fire information"
          )
        }
      ],
      localized_restrictions: [
        forest_detail.fetch(:localized_restrictions).first.merge(
          title: "Burnt Lake half-mile campfire prohibition",
          affected_area: "At and within 1/2 mile of Burnt Lake",
          source_title: "Wilderness Connect"
        )
      ],
      forest_localized_restrictions: forest_detail.fetch(:localized_restrictions),
      datasets: [
        {
          name: "BFP curated launch destinations",
          license_name: "BFP curated",
          license_url: nil,
          attribution_text: "Curated by Big Fluffy Puffy.",
          source_url: nil
        }
      ],
      official_sources: [],
      confidence: 0.9,
      checked_at: "2026-05-03T05:00:00Z",
      map: {center: [45.35, -121.8], localized_rule_count: 2}
    }
  end
end
