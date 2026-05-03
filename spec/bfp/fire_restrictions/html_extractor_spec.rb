require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/extractors/html_extractor"

RSpec.describe BFP::FireRestrictions::Extractors::HtmlExtractor do
  it "extracts title, canonical URL, fire links, and keyword excerpts" do
    html = <<~HTML
      <html>
        <head>
          <title>Willamette Fire</title>
          <link rel="canonical" href="https://www.fs.usda.gov/r06/willamette/fire">
          <meta property="article:modified_time" content="2026-05-01T12:00:00Z">
        </head>
        <body>
          <main>
            <h1>Alerts and Fire Danger Status</h1>
            <a href="/r06/willamette/alerts/stage-1">Stage 1 fire restrictions</a>
            <p>Stage 1 public use restrictions prohibit campfires outside developed campgrounds.</p>
          </main>
        </body>
      </html>
    HTML

    result = described_class.new.extract(html, final_url: "https://www.fs.usda.gov/r06/willamette/fire")

    expect(result[:title]).to eq("Willamette Fire")
    expect(result[:canonical_url]).to eq("https://www.fs.usda.gov/r06/willamette/fire")
    expect(result[:extraction_status]).to eq("ok")
    expect(result[:extracted_text]).to include("Alerts and Fire Danger Status")
    expect(result[:extracted_text]).to include("Stage 1 public use restrictions")
    expect(result[:metadata_json][:keyword_links].first[:href]).to eq(
      "https://www.fs.usda.gov/r06/willamette/alerts/stage-1"
    )
  end

  it "summarizes forest alerts without treating boilerplate as active fire restrictions" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Alerts</h1>
            <h3>Alerts Key</h3>
            <h3>Fire Restriction</h3>
            <p>The USFS initiates restrictions to reduce wildfire risk.</p>
            <h3>Region Alerts</h3>
            <h3>Fireworks and Explosives are always Prohibited</h3>
            <p>Fireworks and explosives are always prohibited on national forest lands.</p>
            <h2>Forest Alerts</h2>
            <h3>Road Closure</h3>
            <p>A road is closed due to flooding.</p>
          </main>
        </body>
      </html>
    HTML

    result = described_class.new.extract(html, final_url: "https://www.fs.usda.gov/r05/example/alerts")

    expect(result[:extracted_text]).to include(
      "No active forest fire restriction alerts were listed in the Forest Alerts section."
    )
    expect(result[:metadata_json][:forest_alert_summary]).to include(
      forest_alerts_count: 1,
      fire_restriction_alerts_count: 0
    )
  end

  it "lists actual forest fire restriction alerts for parser review" do
    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Alerts</h1>
            <h2>Forest Alerts</h2>
            <h3>Snake River Fire Restrictions - 06/01 -09/30</h3>
            <p>Building, maintaining, attending or using a fire, campfire, or stove fire is prohibited within a quarter mile of the Snake River.</p>
          </main>
        </body>
      </html>
    HTML

    result = described_class.new.extract(html, final_url: "https://www.fs.usda.gov/r06/example/alerts")

    expect(result[:extracted_text]).to include("Forest fire restriction alerts listed:")
    expect(result[:extracted_text]).to include("Snake River Fire Restrictions")
    expect(result[:metadata_json][:forest_alert_summary][:fire_restriction_alerts_count]).to eq(1)
  end
end
