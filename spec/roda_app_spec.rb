require "json"
require_relative "spec_helper"
require_relative "../server/roda_app"

RSpec.describe RodaApp do
  include Rack::Test::Methods

  def app
    described_class.app
  end

  it "responds to health checks" do
    get "/health"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to eq("status" => "ok")
  end

  it "exposes a minimal version endpoint" do
    get "/api/version"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include(
      "app" => "big-fluffy-puffy",
      "env" => "test"
    )
  end
end
