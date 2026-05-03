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
end
