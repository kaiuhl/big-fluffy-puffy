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
end
