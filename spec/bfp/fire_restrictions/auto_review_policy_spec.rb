require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/auto_review_policy"

RSpec.describe BFP::FireRestrictions::AutoReviewPolicy do
  let(:policy) { described_class.new }
  let(:official_fire_source) do
    Struct.new(:authority, :source_type, keyword_init: true) do
      def metadata
        {}
      end
    end.new(authority: "official_usfs", source_type: "fs_fire_page")
  end
  let(:official_alerts_source) do
    Struct.new(:authority, :source_type, keyword_init: true) do
      def metadata
        {}
      end
    end.new(authority: "official_usfs", source_type: "fs_alerts_page")
  end
  let(:official_nps_fire_source) do
    Struct.new(:authority, :source_type, keyword_init: true) do
      def metadata
        {}
      end
    end.new(authority: "official_nps", source_type: "nps_fire_page")
  end
  let(:official_nps_alerts_source) do
    Struct.new(:authority, :source_type, keyword_init: true) do
      def metadata
        {}
      end
    end.new(authority: "official_nps", source_type: "nps_alerts_api")
  end

  it "auto-accepts validated high-confidence no-restriction observations from official fire pages" do
    result = parser_result("none", confidence: 0.95, reasons: ["Campfire policy not explicitly stated."])
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: result.fetch("needs_review_reasons"),
      extracted_text: "No public use restrictions in effect."
    )

    expect(status).to eq("auto_accepted")
  end

  it "holds observations when validation found hard evidence problems" do
    result = parser_result("none", confidence: 0.95)
    validation = validation_result(errors: ["None status lacks explicit no-restrictions/lifted/rescinded evidence."])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: result.fetch("needs_review_reasons") + validation.errors,
      extracted_text: "Fire danger is low."
    )

    expect(status).to eq("needs_review")
  end

  it "holds partial-area restrictions for review" do
    result = parser_result("partial", confidence: 0.95, reasons: ["Restriction is geographically limited, not forest-wide."])
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: result.fetch("needs_review_reasons"),
      extracted_text: "Building, maintaining, attending or using a fire is prohibited."
    )

    expect(status).to eq("needs_review")
  end

  it "holds expired restrictive observations for review" do
    result = parser_result("stage_2", confidence: 0.95)
    validation = validation_result(errors: ["Restrictive status effective end is in the past."])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: validation.errors,
      extracted_text: "Stage 2 public use restrictions are in effect. Campfires are prohibited."
    )

    expect(status).to eq("needs_review")
  end

  it "keeps explicit metadata auto-publish support for deterministic sources" do
    source = Struct.new(:authority, :source_type, keyword_init: true) do
      def metadata
        {"auto_publish" => true}
      end
    end.new(authority: "partner_interagency", source_type: "arcgis_feature_layer")

    result = parser_result("none", confidence: 0.95)
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: source,
      result: result,
      validation: validation,
      reasons: [],
      extracted_text: ""
    )

    expect(status).to eq("auto_accepted")
  end

  it "auto-accepts high-confidence advisories from official sources" do
    result = parser_result(
      "advisory",
      confidence: 0.9
    ).merge(
      "evidence_quotes" => ["PUR: Seasonal Restrictions"]
    )
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: [],
      extracted_text: "PUR: Seasonal Restrictions"
    )

    expect(status).to eq("auto_accepted")
  end

  it "auto-accepts high-confidence active restrictions from official NPS fire pages" do
    result = parser_result(
      "full",
      confidence: 0.92
    ).merge(
      "evidence_quotes" => ["All campfires and charcoal fires are prohibited in Mount Rainier National Park."]
    )
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_nps_fire_source,
      result: result,
      validation: validation,
      reasons: [],
      extracted_text: "All campfires and charcoal fires are prohibited in Mount Rainier National Park."
    )

    expect(status).to eq("auto_accepted")
  end

  it "does not auto-accept NPS alerts API none observations from absent-alert summaries alone" do
    result = parser_result(
      "none",
      confidence: 0.95
    ).merge(
      "evidence_quotes" => ["No fire-related NPS alerts were returned by the NPS alerts API."]
    )
    validation = validation_result(errors: ["None status lacks explicit no-restrictions/lifted/rescinded evidence."])

    status = policy.review_status_for_result(
      source: official_nps_alerts_source,
      result: result,
      validation: validation,
      reasons: validation.errors,
      extracted_text: "No fire-related NPS alerts were returned by the NPS alerts API."
    )

    expect(status).to eq("needs_review")
  end

  it "auto-accepts official alerts pages when structured extraction shows no active forest fire restriction alerts" do
    result = parser_result(
      "none",
      confidence: 0.9
    ).merge(
      "evidence_quotes" => ["No active forest fire restriction alerts were listed in the Forest Alerts section."]
    )
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_alerts_source,
      result: result,
      validation: validation,
      reasons: [],
      extracted_text: "No active forest fire restriction alerts were listed in the Forest Alerts section."
    )

    expect(status).to eq("auto_accepted")
  end

  it "holds official alerts-page none observations when the page points to a separate current restrictions source" do
    result = parser_result(
      "none",
      confidence: 0.9
    ).merge(
      "evidence_quotes" => ["No active forest fire restriction alerts were listed in the Forest Alerts section."]
    )
    validation = validation_result(errors: [])

    status = policy.review_status_for_result(
      source: official_alerts_source,
      result: result,
      validation: validation,
      reasons: [],
      extracted_text: "No active forest fire restriction alerts were listed in the Forest Alerts section. IFPLs and Restrictions"
    )

    expect(status).to eq("needs_review")
  end

  it "auto-accepts clear none observations with stale supporting quote mismatch errors" do
    result = parser_result(
      "none",
      confidence: 0.95,
      reasons: ["Evidence quote does not match extracted text: Fireworks and explosives are always prohibited"]
    ).merge(
      "evidence_quotes" => [
        "There are currently no fire restrictions on the Olympic National Forest.",
        "Fireworks and explosives are always prohibited on national forest lands."
      ]
    )
    validation = validation_result(errors: ["Evidence quote does not match extracted text: Fireworks and explosives are always prohibited"])

    status = policy.review_status_for_result(
      source: official_fire_source,
      result: result,
      validation: validation,
      reasons: result.fetch("needs_review_reasons") + validation.errors,
      extracted_text: "There are currently no fire restrictions on the Olympic National Forest."
    )

    expect(status).to eq("auto_accepted")
  end

  def parser_result(status, confidence:, reasons: [])
    {
      "status" => status,
      "confidence" => confidence,
      "evidence_quotes" => [],
      "needs_review_reasons" => reasons
    }
  end

  def validation_result(errors:)
    Object.new.tap do |object|
      object.define_singleton_method(:errors) { errors }
    end
  end
end
