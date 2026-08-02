require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/resolver"

RSpec.describe BFP::FireRestrictions::Resolver do
  let(:resolver) { described_class.new(observation_freshness: nil, localized_rule_resolver: nil) }

  describe "#conflicting?" do
    it "does not conflict when labels differ but the campfire answer agrees" do
      candidates = [
        candidate(status: "stage_2", campfire_policy: "prohibited", source_type: "fs_alerts_page"),
        candidate(status: "full", campfire_policy: "prohibited", source_type: "arcgis_feature_layer")
      ]

      expect(conflicting?(candidates)).to be(false)
    end

    it "conflicts when labels differ and the campfire answers disagree" do
      candidates = [
        candidate(status: "stage_1", campfire_policy: "developed_sites_only", source_type: "fs_alerts_page"),
        candidate(status: "full", campfire_policy: "prohibited", source_type: "fs_fire_info_page")
      ]

      expect(conflicting?(candidates)).to be(true)
    end

    it "conflicts when labels differ and no campfire answer is known" do
      candidates = [
        candidate(status: "stage_1", campfire_policy: "unknown", source_type: "fs_alerts_page"),
        candidate(status: "stage_2", campfire_policy: "unknown", source_type: "fs_fire_info_page")
      ]

      expect(conflicting?(candidates)).to be(true)
    end

    it "does not count a year-round baseline against an active fire order" do
      candidates = [
        candidate(status: "year_round", campfire_policy: "developed_sites_only", source_type: "nps_fire_page"),
        candidate(status: "full", campfire_policy: "prohibited", source_type: "nps_alerts_api")
      ]

      expect(conflicting?(candidates)).to be(false)
    end

    it "still conflicts between a year-round baseline and a relaxed status" do
      candidates = [
        candidate(status: "year_round", campfire_policy: "prohibited", source_type: "nps_fire_page"),
        candidate(status: "none", campfire_policy: "allowed", source_type: "nps_alerts_api")
      ]

      expect(conflicting?(candidates)).to be(true)
    end

    it "does not conflict on a single status" do
      candidates = [
        candidate(status: "stage_2", campfire_policy: "prohibited", source_type: "fs_alerts_page"),
        candidate(status: "stage_2", campfire_policy: "prohibited", source_type: "arcgis_feature_layer")
      ]

      expect(conflicting?(candidates)).to be(false)
    end

    it "ignores unknown-status candidates when a real status exists" do
      candidates = [
        candidate(status: "unknown", campfire_policy: "unknown", source_type: "arcgis_feature_layer"),
        candidate(status: "stage_1", campfire_policy: "prohibited", source_type: "fs_alerts_page")
      ]

      expect(conflicting?(candidates)).to be(false)
    end
  end

  describe "#preferred_candidate" do
    it "prefers the stricter status label when sources agree on the campfire answer" do
      partial = candidate(status: "partial", campfire_policy: "prohibited", source_type: "nps_fire_page")
      full = candidate(status: "full", campfire_policy: "prohibited", source_type: "nps_alerts_api")

      expect(preferred_candidate([partial, full])).to be(full)
    end

    it "breaks status ties by source precedence" do
      alerts = candidate(status: "stage_2", campfire_policy: "prohibited", source_type: "fs_alerts_page")
      arcgis = candidate(status: "stage_2", campfire_policy: "prohibited", source_type: "arcgis_feature_layer")

      expect(preferred_candidate(comparison([alerts, arcgis]))).to be(arcgis)
    end

    it "publishes the active order rather than the year-round baseline" do
      baseline = candidate(status: "year_round", campfire_policy: "developed_sites_only", source_type: "nps_fire_page")
      order = candidate(status: "full", campfire_policy: "prohibited", source_type: "nps_alerts_api")

      expect(preferred_candidate(comparison([baseline, order]))).to be(order)
    end

    it "never selects an unknown-status candidate over a real status" do
      unknown = candidate(status: "unknown", campfire_policy: "unknown", source_type: "arcgis_feature_layer")
      real = candidate(status: "stage_1", campfire_policy: "prohibited", source_type: "fs_alerts_page")

      expect(preferred_candidate(comparison([unknown, real]))).to be(real)
    end

    it "returns nil when no candidate carries a real status" do
      unknown = candidate(status: "unknown", campfire_policy: "unknown", source_type: "fs_alerts_page")

      expect(preferred_candidate(comparison([unknown]))).to be_nil
    end
  end

  describe "#latest_per_source" do
    it "keeps only the newest observation per source" do
      older = per_source_candidate(source_id: 1, created_at: Time.utc(2026, 7, 25))
      newer = per_source_candidate(source_id: 1, created_at: Time.utc(2026, 8, 2))
      other = per_source_candidate(source_id: 2, created_at: Time.utc(2026, 7, 1))

      expect(resolver.send(:latest_per_source, [older, newer, other])).to contain_exactly(newer, other)
    end
  end

  def conflicting?(candidates)
    resolver.send(:conflicting?, candidates)
  end

  def comparison(candidates)
    resolver.send(:comparison_candidates, candidates)
  end

  def preferred_candidate(candidates)
    resolver.send(:preferred_candidate, candidates)
  end

  def candidate(status:, campfire_policy:, source_type:, confidence: 0.95, created_at: Time.utc(2026, 8, 1))
    source = Struct.new(:source_type).new(source_type)
    Struct.new(:status, :campfire_policy, :confidence, :created_at, :restriction_source)
      .new(status, campfire_policy, confidence, created_at, source)
  end

  def per_source_candidate(source_id:, created_at:)
    Struct.new(:restriction_source_id, :created_at).new(source_id, created_at)
  end
end
