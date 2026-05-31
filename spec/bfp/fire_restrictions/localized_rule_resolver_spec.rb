require "sequel"
require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/resolver"
require_relative "../../../lib/bfp/fire_restrictions/localized_rule_resolver"

RSpec.describe BFP::FireRestrictions::Resolver do
  describe "#accepted_candidates" do
    it "ranks official NPS fire sources ahead of alert and conditions fallbacks" do
      precedence = described_class::SOURCE_PRECEDENCE

      expect(precedence.fetch("nps_fire_page")).to be > precedence.fetch("nps_alerts_api")
      expect(precedence.fetch("nps_alerts_api")).to be > precedence.fetch("nps_conditions_page")
      expect(precedence.fetch("nps_fire_page")).to eq(precedence.fetch("fs_fire_page"))
    end

    it "limits forestwide status candidates to forestwide, mixed, or legacy null-scope observations" do
      db = Sequel.mock(host: :postgres, fetch: [])
      land_unit = Struct.new(:id, keyword_init: true).new(id: 7)

      stub_const("BFP::FireRestrictions::RestrictionObservation", db[:restriction_observations])

      described_class.new.send(:accepted_candidates, land_unit)

      sql = db.sqls.last
      expect(sql).to include('("scope" IS NULL) OR ("scope" IN (\'forestwide\', \'mixed\'))')
      expect(sql).to include('"review_status" IN (\'accepted\', \'auto_accepted\')')
    end
  end
end

RSpec.describe BFP::FireRestrictions::LocalizedRuleResolver do
  let(:rule_class) do
    Struct.new(
      :id,
      :status,
      :duration_type,
      :effective_start,
      :effective_end,
      :season_start_month,
      :season_start_day,
      :season_end_month,
      :season_end_day,
      :title,
      keyword_init: true
    )
  end

  it "treats permanent active restrictions as active without date churn" do
    rule = rule_class.new(status: "year_round", duration_type: "permanent")

    expect(active?(rule, on: Date.new(2026, 5, 16))).to be(true)
  end

  it "handles recurring seasonal windows that cross the calendar year" do
    rule = rule_class.new(
      status: "partial",
      duration_type: "seasonal",
      season_start_month: 11,
      season_start_day: 1,
      season_end_month: 4,
      season_end_day: 30
    )

    expect(active?(rule, on: Date.new(2026, 1, 15))).to be(true)
    expect(active?(rule, on: Date.new(2026, 7, 15))).to be(false)
  end

  it "excludes expired temporary rules" do
    rule = rule_class.new(
      status: "stage_2",
      duration_type: "temporary",
      effective_start: Date.new(2025, 7, 1),
      effective_end: Date.new(2025, 9, 1)
    )

    expect(active?(rule, on: Date.new(2026, 5, 16))).to be(false)
  end

  def active?(rule, on:)
    described_class.new.send(:active_rule?, rule, on: on)
  end
end
