require_relative "../config/boot"

class RodaApp < Roda
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
            <title>Fire Restrictions | Big Fluffy Puffy</title>
            <meta
              name="description"
              content="National forest fire restriction status for Big Fluffy Puffy's Pacific Northwest market."
            >
            <link rel="stylesheet" href="/styles/site.css">
          </head>
          <body>
            <div class="page">
              <main class="restrictions-page">
                <header class="restrictions-header">
                  <a href="/">Big Fluffy Puffy</a>
                  <p>Fire Restrictions</p>
                </header>

                <section class="restrictions-intro" aria-labelledby="restrictions-title">
                  <p class="kicker">Official source monitor</p>
                  <h1 id="restrictions-title">National Forest Fire Restrictions</h1>
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
                <header class="site-header" aria-label="Site">
                  <p>Big Fluffy Puffy</p>
                  <p class="brand-code">BFP / PNW / In formation</p>
                </header>

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

  def fire_restriction_records
    require "bfp/fire_restrictions"

    BFP::FireRestrictions::StatusPresenter.new.forests
  rescue Sequel::DatabaseError, LoadError
    []
  end

  def fire_restrictions_page(records)
    return empty_fire_restrictions_message if records.empty?

    groups = partition_fire_restrictions(records)

    <<~HTML
      <section class="restrictions-summary" aria-label="Restriction summary">
        #{restriction_summary(groups)}
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
          <p>#{records.length} #{noun}</p>
        </div>
        <div class="restrictions-table-wrap">
          #{records.empty? ? section_empty_message(empty_message) : fire_restrictions_table(records)}
        </div>
      </section>
    HTML
  end

  def fire_restrictions_table(records)
    rows = records.map { |forest| fire_restrictions_row(forest) }.join

    <<~HTML
      <table class="restrictions-table">
        <thead>
          <tr>
            <th scope="col">Forest</th>
            <th scope="col">Status</th>
            <th scope="col">Campfires</th>
            <th scope="col">Source</th>
            <th scope="col">Updated</th>
            <th scope="col">Evidence</th>
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
          <small>#{h(forest[:region_code])} / #{h(forest[:market_bucket].to_s.tr("_", " "))}</small>
        </th>
        <td><strong>#{h(status_label(forest))}</strong></td>
        <td>#{h(labelize(forest[:campfire_policy]))}</td>
        <td>#{source_link(source)}</td>
        <td>#{h(timestamp_for(forest, source))}</td>
        <td>#{h(evidence_summary(forest))}</td>
      </tr>
    HTML
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

  def timestamp_for(forest, source)
    forest[:last_checked_at] || source&.fetch(:last_checked_at, nil) || "Never"
  end

  def evidence_summary(forest)
    forest[:summary] || Array(forest[:evidence_quotes]).first || review_label(forest)
  end

  def status_label(forest)
    return "Needs Review" unless published_status?(forest)

    labelize(forest[:status])
  end

  def review_label(forest)
    return "Published" if published_status?(forest)

    labelize(forest[:review_status])
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
