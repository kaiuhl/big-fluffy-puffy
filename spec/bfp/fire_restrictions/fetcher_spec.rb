require "net/http"
require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/fetcher"

RSpec.describe BFP::FireRestrictions::Fetcher do
  around do |example|
    previous = ENV["NPS_API_KEY"]
    example.run
  ensure
    if previous.nil?
      ENV.delete("NPS_API_KEY")
    else
      ENV["NPS_API_KEY"] = previous
    end
  end

  it "adds the NPS API key header for NPS alerts API sources" do
    ENV["NPS_API_KEY"] = "test-nps-key"
    request = Net::HTTP::Get.new(URI("https://developer.nps.gov/api/v1/alerts?parkCode=MORA"))

    described_class.new.send(:apply_nps_api_key, request, source("nps_alerts_api"))

    expect(request["X-Api-Key"]).to eq("test-nps-key")
  end

  it "requires an NPS API key for NPS alerts API sources" do
    ENV.delete("NPS_API_KEY")
    request = Net::HTTP::Get.new(URI("https://developer.nps.gov/api/v1/alerts?parkCode=MORA"))

    expect do
      described_class.new.send(:apply_nps_api_key, request, source("nps_alerts_api"))
    end.to raise_error(RuntimeError, /NPS_API_KEY/)
  end

  it "does not add an NPS API key header for non-NPS sources" do
    ENV["NPS_API_KEY"] = "test-nps-key"
    request = Net::HTTP::Get.new(URI("https://www.fs.usda.gov/r06/willamette/fire"))

    described_class.new.send(:apply_nps_api_key, request, source("fs_fire_page"))

    expect(request["X-Api-Key"]).to be_nil
  end

  def source(source_type)
    Struct.new(:source_type).new(source_type)
  end
end
