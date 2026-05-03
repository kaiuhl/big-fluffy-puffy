require_relative "../../spec_helper"
require "bfp/climate/low_sparkline"

RSpec.describe BFP::Climate::LowSparkline do
  it "renders compact available-band SVG with midpoint labels and month context" do
    html = described_class.render(
      month_name: "September",
      bands: [
        {elevation_min_ft: 0, elevation_max_ft: 2000, mean_low_f: 47.96},
        {elevation_min_ft: 2000, elevation_max_ft: 4000, mean_low_f: 46.48},
        {elevation_min_ft: 4000, elevation_max_ft: 6000, mean_low_f: 42.43},
        {elevation_min_ft: 6000, elevation_max_ft: 8000, mean_low_f: 37.97}
      ]
    )

    expect(html).to include('class="climate-low-sparkline"')
    expect(html).not_to include("Average September lows</text>")
    expect(html).to include("1K")
    expect(html).to include("3K")
    expect(html).to include("5K")
    expect(html).to include("7K")
    expect(html).to include("48&#176;")
    expect(html).to include("aria-label=\"Average September overnight lows by elevation: 1K 48 degrees Fahrenheit, 3K 46 degrees Fahrenheit, 5K 42 degrees Fahrenheit, 7K 38 degrees Fahrenheit\"")
  end

  it "compresses spacing instead of reserving missing elevation bands" do
    html = described_class.render(
      month_name: "May",
      bands: [
        {elevation_min_ft: 2000, elevation_max_ft: 4000, mean_low_f: 36.21},
        {elevation_min_ft: 4000, elevation_max_ft: 6000, mean_low_f: 32.48},
        {elevation_min_ft: 6000, elevation_max_ft: 8000, mean_low_f: 29.15}
      ]
    )

    expect(html).to include('x1="8"')
    expect(html).to include('x1="77"')
    expect(html).to include('x1="146"')
    expect(html).not_to include(">1K</text>")
  end
end
