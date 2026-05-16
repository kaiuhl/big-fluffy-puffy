require_relative "../../spec_helper"
require "bfp/fire_restrictions/fire_use_sparkline"

RSpec.describe BFP::FireRestrictions::FireUseSparkline do
  let(:rule) do
    {
      campfire_policy: "prohibited",
      gas_stove_policy: "allowed_with_shutoff_valve",
      alcohol_stove_policy: "unknown",
      charcoal_policy: "prohibited",
      solid_fuel_stove_policy: "prohibited",
      wood_stove_policy: "prohibited",
      stove_shutoff_valve_required: true
    }
  end

  it "renders a compact one-row fire-use SVG with accessible policy detail" do
    html = described_class.render(rule)

    expect(html).to include('class="fire-use-sparkline"')
    expect(html).to include("--fire-use-count: 5")
    expect(html).to include("--fire-use-width: 258px")
    expect(html).to include("fire-use-point-prohibited")
    expect(html).to include("fire-use-point-allowed")
    expect(html).not_to include("fire-use-point-unknown")
    expect(html).not_to include("fire-use-guide")
    expect(html).to include(">Campfires</span>")
    expect(html).to include(">Gas stoves</span>")
    expect(html).to include(">Solid fuel stoves</span>")
    expect(html).not_to include(">Alcohol stoves</span>")
    expect(html).to include('title="Campfires prohibited. Gas stoves allowed with shutoff valve. Alcohol stoves unknown. Charcoal, solid fuel stoves, and wood stoves prohibited."')
    expect(html).to include('aria-label="Fire use: Campfires prohibited. Gas stoves allowed with shutoff valve. Alcohol stoves unknown. Charcoal, solid fuel stoves, and wood stoves prohibited."')
  end

  it "summarizes the user-facing takeaway without appending shutoff rules to prohibited fuels" do
    expect(described_class.summary(rule)).to eq(
      "Campfires prohibited. Gas stoves allowed with shutoff valve. Alcohol stoves unknown. Charcoal, solid fuel stoves, and wood stoves prohibited."
    )
  end

  it "renders nothing when every policy is unknown" do
    expect(
      described_class.render(
        campfire_policy: "unknown",
        gas_stove_policy: "unknown",
        alcohol_stove_policy: "unknown",
        charcoal_policy: "unknown",
        solid_fuel_stove_policy: "unknown",
        wood_stove_policy: "unknown"
      )
    ).to eq("")
  end

  it "treats fire-pan requirements as limited campfire use" do
    html = described_class.render(rule.merge(campfire_policy: "fire_pan_required"))

    expect(html).to include("fire-use-point-limited")
    expect(described_class.summary(rule.merge(campfire_policy: "fire_pan_required"))).to start_with("Campfires allowed only with a fire pan.")
  end
end
