require_relative "../../spec_helper"
require "bfp/fire_restrictions/status_display"

RSpec.describe BFP::FireRestrictions::StatusDisplay do
  describe ".campfire_policy" do
    it "treats no published restrictions as campfires allowed when parser policy is unknown" do
      expect(
        described_class.campfire_policy(status: "none", campfire_policy: "unknown")
      ).to eq("allowed")
    end

    it "keeps explicit campfire policies" do
      expect(
        described_class.campfire_policy(status: "stage_1", campfire_policy: "developed_sites_only")
      ).to eq("developed_sites_only")
    end
  end

  describe ".checked_date_label" do
    it "formats UTC calendar dates so map and table labels match" do
      expect(described_class.checked_date_label("2026-05-03T06:00:05Z")).to eq("May 3, 2026")
    end
  end

  describe ".stove_policy_label" do
    it "labels shutoff-valve stove allowances clearly" do
      expect(
        described_class.stove_policy_label("allowed_with_shutoff_valve")
      ).to eq("Allowed with shutoff valve")
    end
  end

  describe ".duration_label" do
    it "labels permanent localized rules without date churn" do
      expect(described_class.duration_label(duration_type: "permanent")).to eq("Permanent")
    end

    it "labels date-limited temporary rules" do
      expect(
        described_class.duration_label(
          duration_type: "temporary",
          effective_start: "2026-07-01",
          effective_end: "2026-09-01"
        )
      ).to eq("Jul 1, 2026 to Sep 1, 2026")
    end
  end
end
