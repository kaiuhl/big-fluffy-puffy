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
end
