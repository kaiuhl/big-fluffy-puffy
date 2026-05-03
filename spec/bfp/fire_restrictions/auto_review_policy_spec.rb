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
