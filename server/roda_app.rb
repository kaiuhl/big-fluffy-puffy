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
            <main class="restrictions-page">
              <header class="restrictions-header">
                <a href="/">Big Fluffy Puffy</a>
                <p>Fire Restrictions</p>
              </header>

              <section class="restrictions-intro" aria-labelledby="restrictions-title">
                <p class="kicker">Official source monitor</p>
                <h1 id="restrictions-title">National Forest Fire Restrictions</h1>
              </section>

              <section class="restrictions-table-wrap" aria-label="National forest fire restrictions">
                #{fire_restrictions_table(records)}
              </section>
            </main>
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

  def fire_restrictions_table(records)
    return empty_fire_restrictions_message if records.empty?

    rows = records.map do |forest|
      source_links = forest[:sources].first(4).map do |source|
        %(<a href="#{h(source[:url])}" rel="noreferrer">#{h(source[:name])}</a>)
      end.join(" ")

      <<~HTML
        <tr>
          <th scope="row">
            <span>#{h(forest[:name])}</span>
            <small>#{h(forest[:region_code])} / #{h(forest[:market_bucket].to_s.tr("_", " "))}</small>
          </th>
          <td><strong>#{h(labelize(forest[:status]))}</strong></td>
          <td>#{h(labelize(forest[:campfire_policy]))}</td>
          <td>#{h(confidence_label(forest[:confidence]))}</td>
          <td>#{h(labelize(forest[:review_status]))}</td>
          <td>#{h(forest[:last_checked_at] || "Never")}</td>
          <td>
            #{source_links}
            #{primary_source_link(forest)}
          </td>
          <td>#{h(forest[:summary] || forest[:evidence_quotes].first || "")}</td>
        </tr>
      HTML
    end.join

    <<~HTML
      <table class="restrictions-table">
        <thead>
          <tr>
            <th scope="col">Forest</th>
            <th scope="col">Status</th>
            <th scope="col">Campfires</th>
            <th scope="col">Confidence</th>
            <th scope="col">Review</th>
            <th scope="col">Last Checked</th>
            <th scope="col">Sources</th>
            <th scope="col">Evidence</th>
          </tr>
        </thead>
        <tbody>
          #{rows}
        </tbody>
      </table>
    HTML
  end

  def empty_fire_restrictions_message
    <<~HTML
      <div class="empty-state">
        <p>No fire restriction sources have been seeded yet.</p>
      </div>
    HTML
  end

  def primary_source_link(forest)
    return "" unless forest[:source_url]

    %(<a href="#{h(forest[:source_url])}" rel="noreferrer">Current evidence</a>)
  end

  def labelize(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def confidence_label(value)
    return "Unknown" unless value

    "#{(value.to_f * 100).round}%"
  end

  def h(value)
    Rack::Utils.escape_html(value.to_s)
  end
end
