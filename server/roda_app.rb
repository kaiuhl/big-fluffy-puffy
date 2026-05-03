require_relative "../config/boot"

class RodaApp < Roda
  plugin :common_logger
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
          </head>
          <body>
            <main>
              <h1>Big Fluffy Puffy</h1>
              <p>Fireless camp culture for the Pacific Northwest.</p>
            </main>
          </body>
        </html>
      HTML
    end
  end
end
