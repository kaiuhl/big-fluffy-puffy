require_relative "../../spec_helper"
require_relative "../../../config/boot"
require_relative "../../../lib/bfp/fire_restrictions/source_parser"

RSpec.describe BFP::FireRestrictions::SourceParser do
  around do |example|
    previous = ENV["LLM_ESCALATION_ENABLED"]
    ENV.delete("LLM_ESCALATION_ENABLED")
    example.run
  ensure
    if previous.nil?
      ENV.delete("LLM_ESCALATION_ENABLED")
    else
      ENV["LLM_ESCALATION_ENABLED"] = previous
    end
  end

  let(:parser) { described_class.new(parser_client: Object.new, validator: Object.new) }
  let(:source) { Struct.new(:source_type, :id, keyword_init: true).new(source_type: "fs_fire_info_page", id: 1) }
  let(:land_unit) { Struct.new(:id, keyword_init: true).new(id: 1) }

  it "keeps escalation disabled by default even when the primary result is uncertain" do
    result = parser_result("unknown", confidence: 0.2)
    validation = validation_result(false)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(false)
  end

  it "allows escalation when explicitly enabled and a trigger is present" do
    ENV["LLM_ESCALATION_ENABLED"] = "true"
    result = parser_result("unknown", confidence: 0.2)
    validation = validation_result(true)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(true)
  end

  it "does not escalate parser failures" do
    ENV["LLM_ESCALATION_ENABLED"] = "true"
    result = parser_result("unknown", confidence: 0.0, reasons: ["LLM parsing failed: AccessDenied"])
    validation = validation_result(false)

    expect(should_escalate?(result, validation, "Campfire restrictions may apply.")).to be(false)
  end

  it "passes extracted text into the auto-review policy" do
    policy = Object.new
    parser = described_class.new(parser_client: Object.new, validator: Object.new, auto_review_policy: policy)
    result = parser_result("none", confidence: 0.95)
    validation = validation_result(true, errors: [])
    captured_text = nil

    policy.define_singleton_method(:review_status_for_result) do |extracted_text:, **|
      captured_text = extracted_text
      "auto_accepted"
    end

    status = parser.send(
      :review_status_for,
      source,
      result,
      validation,
      [],
      extracted_text: "No fire restrictions are in effect."
    )

    expect(status).to eq("auto_accepted")
    expect(captured_text).to eq("No fire restrictions are in effect.")
  end

  def should_escalate?(result, validation, text)
    parser.send(:should_escalate?, result, validation, text, source, land_unit)
  end

  def parser_result(status, confidence:, reasons: [])
    {
      "status" => status,
      "confidence" => confidence,
      "needs_review_reasons" => reasons
    }
  end

  def validation_result(valid, errors: [])
    Object.new.tap do |object|
      object.define_singleton_method(:valid?) { valid }
      object.define_singleton_method(:errors) { errors }
    end
  end
end
