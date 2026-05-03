require_relative "../config/boot"
require "bfp/fire_restrictions/status_display"
require "time"

class RodaApp < Roda
  NAV_LINKS = [
    {href: "/", label: "Home"},
    {href: "/fire-restrictions", label: "Fire Restrictions"}
  ].freeze

  STATE_LABELS = {
    "or" => "OR",
    "wa" => "WA",
    "ca" => "CA",
    "other" => "Other"
  }.freeze
  STATE_NAMES = {
    "or" => "Oregon",
    "wa" => "Washington",
    "ca" => "California",
    "other" => "Other"
  }.freeze
  STATE_ORDER = %w[or wa ca other].freeze
  STATE_BY_MARKET_BUCKET = {
    "oregon" => "or",
    "washington" => "wa",
    "northern_california" => "ca",
    "extended_tahoe" => "ca"
  }.freeze
  STATE_BY_LAND_UNIT_SLUG = {
    "colville" => "wa",
    "deschutes" => "or",
    "fremont-winema" => "or",
    "gifford-pinchot" => "wa",
    "malheur" => "or",
    "mt-baker-snoqualmie" => "wa",
    "mt-hood" => "or",
    "ochoco-crooked-river" => "or",
    "okanogan-wenatchee" => "wa",
    "olympic" => "wa",
    "rogue-river-siskiyou" => "or",
    "siuslaw" => "or",
    "umatilla" => "or",
    "umpqua" => "or",
    "wallowa-whitman" => "or",
    "willamette" => "or",
    "klamath" => "ca",
    "six-rivers" => "ca",
    "shasta-trinity" => "ca",
    "mendocino" => "ca",
    "modoc" => "ca",
    "lassen" => "ca",
    "plumas" => "ca",
    "tahoe" => "ca",
    "eldorado" => "ca",
    "lake-tahoe-basin" => "ca"
  }.freeze

  opts[:root] = BFP.root

  plugin :common_logger
  plugin :head
  plugin :public

  route do |r|
    r.public

    r.get "health" do
      response["Content-Type"] = "application/json"
      JSON.generate(status: "ok")
    end

    r.on "api" do
      r.get "version" do
        response["Content-Type"] = "application/json"
        JSON.generate(app: "big-fluffy-puffy", env: BFP.env)
      end

      r.on "fire-restrictions" do
        r.get "forests" do
          response["Content-Type"] = "application/json"
          JSON.generate(forests: fire_restriction_records)
        end

        r.get "map" do
          response["Content-Type"] = "application/geo+json"
          JSON.generate(fire_restriction_map)
        end
      end
    end

    r.get "fire-restrictions" do
      response["Content-Type"] = "text/html"
      records = fire_restriction_records

      <<~HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>PNW Fire Restrictions | Big Fluffy Puffy</title>
            <meta
              name="description"
              content="Pacific Northwest fire restriction status for Big Fluffy Puffy's launch market."
            >
            <link rel="stylesheet" href="/vendor/leaflet/leaflet.css">
            <link rel="stylesheet" href="/styles/site.css">
            <script src="/vendor/leaflet/leaflet.js" defer></script>
            <script src="/scripts/fire-restrictions.js" defer></script>
          </head>
          <body>
            <div class="page">
              <main class="restrictions-page">
                #{site_header(current_path: "/fire-restrictions")}

                <section class="restrictions-intro" aria-labelledby="restrictions-title">
                  <p class="kicker">Official source monitor</p>
                  <h1 id="restrictions-title">PNW Fire Restrictions</h1>
                  <p>
                    Published forest-wide fire restriction status for Oregon, Washington, and Northern California.
                    Unknown entries need source review before they become public claims.
                  </p>
                </section>

                #{fire_restrictions_page(records)}
              </main>
            </div>
          </body>
        </html>
      HTML
    end

    r.root do
      response["Content-Type"] = "text/html"

      <<~HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Big Fluffy Puffy</title>
            <meta
              name="description"
              content="Big Fluffy Puffy is a nonprofit building fireless camp culture in the Pacific Northwest."
            >
            <link rel="stylesheet" href="/styles/site.css">
          </head>
          <body>
            <div class="page">
              <main class="landing">
                #{site_header(current_path: "/")}

                <section class="hero" aria-labelledby="page-title">
                  <div class="nameplate">
                    <p class="kicker">Skip the campfire. Pack the warmth.</p>
                    <h1 id="page-title">Big Fluffy Puffy</h1>
                  </div>

                  <div class="mission" aria-label="Mission">
                    <p class="mission-label">Mission</p>
                    <div class="mission-copy">
                      <p class="mission-statement">
                        Big Fluffy Puffy is a nonprofit building fireless camp culture for the Pacific Northwest.
                      </p>
                      <p class="supporting-copy">
                        We advocate for a simple shift outside: carry enough warmth to enjoy the night without a wood fire. Better insulation, better habits, fewer ignition points. The fuller site is coming soon.
                      </p>
                      <p class="status">More soon</p>
                    </div>
                  </div>
                </section>

                <footer class="site-footer">
                  <p>Oregon / Washington / Northern California</p>
                  <p>The forest does not need your fire.</p>
                </footer>
              </main>
            </div>
          </body>
        </html>
      HTML
    end
  end

  private

  def site_header(current_path:)
    <<~HTML
      <header class="site-header" aria-label="Site">
        <a class="site-brand" href="/">Big Fluffy Puffy</a>
        <nav class="site-nav" aria-label="Primary">
          <ul>
            #{nav_items(current_path)}
          </ul>
        </nav>
      </header>
    HTML
  end

  def nav_items(current_path)
    NAV_LINKS.map do |link|
      current = link.fetch(:href) == current_path
      aria_current = current ? %( aria-current="page") : ""
      class_name = current ? %( class="site-nav-active") : ""

      <<~HTML
        <li>
          <a href="#{h(link.fetch(:href))}"#{class_name}#{aria_current}>#{h(link.fetch(:label))}</a>
        </li>
      HTML
    end.join
  end

  def fire_restriction_records
    require "bfp/fire_restrictions"

    BFP::FireRestrictions::StatusPresenter.new.forests
  rescue Sequel::DatabaseError, LoadError
    []
  end

  def fire_restriction_map
    require "bfp/fire_restrictions/map_presenter"

    BFP::FireRestrictions::MapPresenter.new(records: fire_restriction_records).geojson
  rescue Sequel::DatabaseError, LoadError
    {type: "FeatureCollection", features: []}
  end

  def fire_restrictions_page(records)
    return empty_fire_restrictions_message if records.empty?

    groups = partition_fire_restrictions(records)

    <<~HTML
      <section class="restrictions-summary" aria-label="Restriction summary">
        #{restriction_summary(groups)}
      </section>

      #{fire_restrictions_map_section}

      <section class="restrictions-filter" aria-labelledby="restrictions-filter-label">
        <label id="restrictions-filter-label" for="restrictions-search">Search Forests</label>
        <input
          id="restrictions-search"
          name="q"
          type="search"
          autocomplete="off"
          placeholder="Forest, state, source, policy"
        >
        <p id="restrictions-filter-status" aria-live="polite">
          Showing #{forest_count(records.length)}.
        </p>
      </section>

      <div class="restrictions-sections">
        #{fire_restrictions_section(
          id: "active-restrictions",
          title: "Active Restrictions",
          records: groups.fetch(:active),
          tone: "active",
          empty_message: "No published active forest-wide restrictions."
        )}
        #{fire_restrictions_section(
          id: "no-restrictions",
          title: "No Published Restrictions",
          records: groups.fetch(:none),
          tone: "none",
          empty_message: "No forests have a published no-restrictions status yet."
        )}
        #{fire_restrictions_section(
          id: "needs-review",
          title: "Needs Review / Unknown",
          records: groups.fetch(:unknown),
          tone: "unknown",
          empty_message: "All active forests have a published status."
        )}
      </div>
    HTML
  end

  def fire_restrictions_map_section
    <<~HTML
      <section class="restrictions-map-section" aria-labelledby="restrictions-map-title">
        <div class="restrictions-map-heading">
          <div>
            <p class="summary-kicker">Map overview</p>
            <h2 id="restrictions-map-title">Forest Status Map</h2>
          </div>
          <ul class="restrictions-map-legend" aria-label="Map legend">
            <li><span class="map-legend-swatch map-legend-active" aria-hidden="true"></span>Active restrictions</li>
            <li><span class="map-legend-swatch map-legend-none" aria-hidden="true"></span>No published restrictions</li>
            <li><span class="map-legend-swatch map-legend-unknown" aria-hidden="true"></span>Needs review / unknown</li>
          </ul>
        </div>
        <div
          id="restrictions-map"
          class="restrictions-map"
          data-map-endpoint="/api/fire-restrictions/map"
          role="img"
          aria-label="Map of Pacific Northwest forest fire restriction statuses"
        ></div>
      </section>
    HTML
  end

  def partition_fire_restrictions(records)
    records.each_with_object({active: [], none: [], unknown: []}) do |forest, groups|
      if published_status?(forest) && forest[:status].to_s == "none"
        groups[:none] << forest
      elsif published_status?(forest) && forest[:status].to_s != "unknown"
        groups[:active] << forest
      else
        groups[:unknown] << forest
      end
    end
  end

  def published_status?(forest)
    %w[accepted auto_accepted].include?(forest[:review_status].to_s)
  end

  def restriction_summary(groups)
    active_count = groups.fetch(:active).length
    none_count = groups.fetch(:none).length
    unknown_count = groups.fetch(:unknown).length

    if active_count.zero?
      <<~HTML
        <p class="summary-kicker">Clear for now</p>
        <p class="summary-statement">No published forest-wide restrictions right now.</p>
        <p class="summary-detail">
          #{forest_count(none_count)} have published no-restriction status; #{forest_count(unknown_count)} still need review.
        </p>
      HTML
    else
      <<~HTML
        <p class="summary-kicker">Restriction watch</p>
        <p class="summary-statement">#{forest_count(active_count)} have published active restrictions.</p>
        <p class="summary-detail">
          #{forest_count(none_count)} show no published restrictions; #{forest_count(unknown_count)} still need review.
        </p>
      HTML
    end
  end

  def fire_restrictions_section(id:, title:, records:, tone:, empty_message:)
    noun = (records.length == 1) ? "forest" : "forests"

    <<~HTML
      <section class="restrictions-section restrictions-section-#{h(tone)}" aria-labelledby="#{h(id)}">
        <div class="restrictions-section-heading">
          <h2 id="#{h(id)}">#{h(title)}</h2>
          <p class="restrictions-section-count" data-total="#{records.length}">#{records.length} #{noun}</p>
        </div>
        <div class="restrictions-table-wrap">
          #{records.empty? ? section_empty_message(empty_message) : "#{fire_restrictions_table(records)}#{filter_empty_message}"}
        </div>
      </section>
    HTML
  end

  def fire_restrictions_table(records)
    rows = region_state_sorted_records(records).map { |forest| fire_restrictions_row(forest) }.join

    <<~HTML
      <table class="restrictions-table">
        <thead>
          <tr>
            <th scope="col">Forest</th>
            <th scope="col">Campfires</th>
            <th scope="col">Source</th>
            <th scope="col">Checked</th>
            <th scope="col">Note</th>
          </tr>
        </thead>
        <tbody>
          #{rows}
        </tbody>
      </table>
    HTML
  end

  def fire_restrictions_row(forest)
    source = preferred_source(forest)

    <<~HTML
      <tr>
        <th scope="row">
          <span>#{h(forest[:name])}</span>
          <small>#{h(region_state_label(forest))}</small>
        </th>
        <td data-label="Campfires">#{h(labelize(campfire_policy_for(forest)))}</td>
        <td data-label="Source">#{source_link(source)}</td>
        <td data-label="Checked">#{checked_at_cell(forest, source)}</td>
        <td data-label="Note">#{h(restriction_note(forest))}</td>
      </tr>
    HTML
  end

  def region_state_sorted_records(records)
    records.sort_by do |forest|
      state = state_code(forest)
      [STATE_ORDER.index(state) || STATE_ORDER.length, forest[:name].to_s]
    end
  end

  def region_state_label(forest)
    region = forest[:region_code].to_s
    state = STATE_NAMES.fetch(state_code(forest))

    [region, state].reject(&:empty?).join(" / ")
  end

  def state_code(forest)
    STATE_BY_LAND_UNIT_SLUG.fetch(forest[:slug].to_s) do
      STATE_BY_MARKET_BUCKET.fetch(forest[:market_bucket].to_s, "other")
    end
  end

  def empty_fire_restrictions_message
    <<~HTML
      <div class="empty-state">
        <p>No fire restriction sources have been seeded yet.</p>
      </div>
    HTML
  end

  def section_empty_message(message)
    <<~HTML
      <div class="empty-state empty-state-section">
        <p>#{h(message)}</p>
      </div>
    HTML
  end

  def filter_empty_message
    <<~HTML
      <div class="empty-state empty-state-section restrictions-filter-empty" hidden>
        <p>No matching forests.</p>
      </div>
    HTML
  end

  def preferred_source(forest)
    return {url: forest[:source_url], name: forest[:source_title] || "Current evidence", last_checked_at: forest[:last_checked_at]} if forest[:source_url]

    sources = Array(forest[:sources])
    sources.min_by { |source| [source_rank(source), source[:name].to_s] }
  end

  def source_rank(source)
    {
      "fs_fire_info_page" => 0,
      "fs_fire_page" => 1,
      "fs_alerts_page" => 2,
      "fs_release_page" => 3
    }.fetch(source[:source_type].to_s, 9)
  end

  def source_link(source)
    return "Not checked yet" unless source && source[:url]

    %(<a href="#{h(source[:url])}" rel="noreferrer">#{h(source[:name])}</a>)
  end

  def checked_at_cell(forest, source)
    checked_at = checked_at_for(forest, source)
    return "not checked" unless checked_at

    %(<time datetime="#{h(checked_at)}">#{h(date_label(checked_at))}</time>)
  end

  def checked_at_for(forest, source)
    forest[:last_checked_at] || source&.fetch(:last_checked_at, nil)
  end

  def date_label(value)
    BFP::FireRestrictions::StatusDisplay.checked_date_label(value)
  end

  def campfire_policy_for(forest)
    BFP::FireRestrictions::StatusDisplay.campfire_policy(
      status: forest[:status],
      campfire_policy: forest[:campfire_policy]
    )
  end

  def restriction_note(forest)
    summary = forest[:summary].to_s.strip
    return summary unless summary.empty?

    evidence = Array(forest[:evidence_quotes]).find { |quote| !quote.to_s.strip.empty? }
    return evidence if evidence

    published_status?(forest) ? "Published source reviewed." : "Needs source review."
  end

  def labelize(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def forest_count(count)
    "#{count} #{(count == 1) ? "forest" : "forests"}"
  end

  def h(value)
    Rack::Utils.escape_html(value.to_s)
  end
end
