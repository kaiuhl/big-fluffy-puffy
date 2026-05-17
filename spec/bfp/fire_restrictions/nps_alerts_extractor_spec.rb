require "json"
require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/extractors/nps_alerts_extractor"

RSpec.describe BFP::FireRestrictions::Extractors::NpsAlertsExtractor do
  it "extracts fire-related NPS alerts into parser-friendly text" do
    body = JSON.generate(
      "data" => [
        {
          "title" => "Parkwide Fire Ban",
          "category" => "Danger",
          "parkCode" => ["MORA"],
          "description" => "All campfires and charcoal fires are prohibited in Mount Rainier National Park.",
          "url" => "https://www.nps.gov/mora/planyourvisit/conditions.htm",
          "lastIndexedDate" => "2026-05-01T12:00:00Z"
        },
        {
          "title" => "Road construction",
          "category" => "Information",
          "description" => "Expect delays."
        }
      ]
    )

    result = described_class.new.extract(body, final_url: "https://developer.nps.gov/api/v1/alerts?parkCode=MORA")

    expect(result[:extraction_status]).to eq("ok")
    expect(result[:modified_at].utc.iso8601).to eq("2026-05-01T12:00:00Z")
    expect(result[:extracted_text]).to include("NPS Alert Summary:")
    expect(result[:extracted_text]).to include("Fire-related NPS alerts returned:")
    expect(result[:extracted_text]).to include("Parkwide Fire Ban")
    expect(result[:extracted_text]).not_to include("Road construction")
    expect(result[:metadata_json]).to include(
      nps_alert_count: 2,
      nps_fire_alert_count: 1,
      nps_fire_alert_titles: ["Parkwide Fire Ban"]
    )
  end

  it "does not turn an empty fire-alert result into no-restrictions evidence" do
    body = JSON.generate("data" => [{"title" => "Road construction", "description" => "Expect delays."}])

    result = described_class.new.extract(body, final_url: "https://developer.nps.gov/api/v1/alerts?parkCode=CRLA")

    expect(result[:extraction_status]).to eq("ok")
    expect(result[:extracted_text]).to include("No fire-related NPS alerts were returned by the NPS alerts API.")
    expect(result[:extracted_text]).not_to include("No active forest fire restriction alerts were listed")
  end

  it "marks invalid JSON for review" do
    result = described_class.new.extract("<html></html>", final_url: "https://developer.nps.gov/api/v1/alerts?parkCode=OLYM")

    expect(result[:extraction_status]).to eq("needs_review")
    expect(result[:extraction_error]).to include("not valid JSON")
  end
end
