require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/parse_decision"

RSpec.describe BFP::FireRestrictions::ParseDecision do
  let(:fetch_class) do
    Struct.new(
      :id,
      :restriction_source_id,
      :error_class,
      :source_document,
      :content_changed,
      keyword_init: true
    )
  end

  it "does not parse errored fetches" do
    fetch = fetch_class.new(error_class: "Timeout", source_document: Object.new, content_changed: true)

    expect(described_class.parse_fetch?(fetch)).to be(false)
  end

  it "does not parse fetches without a source document" do
    fetch = fetch_class.new(error_class: nil, source_document: nil, content_changed: true)

    expect(described_class.parse_fetch?(fetch)).to be(false)
  end

  it "parses changed documents" do
    fetch = fetch_class.new(error_class: nil, source_document: Object.new, content_changed: true)

    expect(described_class.parse_fetch?(fetch)).to be(true)
  end

  it "parses the first successful document for a source" do
    fetch = fetch_class.new(
      id: 10,
      restriction_source_id: 20,
      error_class: nil,
      source_document: Object.new,
      content_changed: false
    )
    observation_model = Class.new do
      def self.where(_conditions)
        []
      end
    end

    expect(described_class.parse_fetch?(fetch, observation_model: observation_model)).to be(true)
  end

  it "does not parse unchanged documents after the source already has observations" do
    fetch = fetch_class.new(
      id: 10,
      restriction_source_id: 20,
      error_class: nil,
      source_document: Object.new,
      content_changed: false
    )
    observation_model = Class.new do
      def self.where(_conditions)
        [Object.new]
      end
    end

    expect(described_class.parse_fetch?(fetch, observation_model: observation_model)).to be(false)
  end

  it "parses unchanged documents once parsing is enabled when the source only has disabled-parser placeholders" do
    fetch = fetch_class.new(
      id: 10,
      restriction_source_id: 20,
      error_class: nil,
      source_document: Object.new,
      content_changed: false
    )
    placeholder = Struct.new(:needs_review_reasons).new(["LLM parsing is disabled or unavailable."])
    observation_model = Class.new do
      define_singleton_method(:where) do |conditions|
        (conditions == {source_fetch_id: 10}) ? [] : [placeholder]
      end
    end

    previous = ENV["LLM_PARSE_ENABLED"]
    ENV["LLM_PARSE_ENABLED"] = "true"
    begin
      expect(described_class.parse_fetch?(fetch, observation_model: observation_model)).to be(true)
    ensure
      ENV["LLM_PARSE_ENABLED"] = previous
    end
  end
end
