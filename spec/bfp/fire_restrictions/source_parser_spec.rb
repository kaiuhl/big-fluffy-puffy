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

  def validation_result(valid)
    Object.new.tap do |object|
      object.define_singleton_method(:valid?) { valid }
    end
  end
end
