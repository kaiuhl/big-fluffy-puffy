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
      reasons: result.fetch("needs_review_reasons")
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
      reasons: result.fetch("needs_review_reasons") + validation.errors
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
      reasons: result.fetch("needs_review_reasons")
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
      reasons: []
    )

    expect(status).to eq("auto_accepted")
  end

  def parser_result(status, confidence:, reasons: [])
    {
      "status" => status,
      "confidence" => confidence,
      "needs_review_reasons" => reasons
    }
  end

  def validation_result(errors:)
    Object.new.tap do |object|
      object.define_singleton_method(:errors) { errors }
    end
  end
end
