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

  it "exposes the fire restriction forests endpoint" do
    get "/api/fire-restrictions/forests"

    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to include("forests")
  end

  it "serves the fire restrictions page shell" do
    get "/fire-restrictions"

    expect(last_response).to be_ok
    expect(last_response.body).to include("National Forest Fire Restrictions")
  end

  it "serves the initial landing page" do
    get "/"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Big Fluffy Puffy")
    expect(last_response.body).to include("Skip the campfire. Pack the warmth.")
    expect(last_response.body).to include("nonprofit building fireless camp culture")
  end

  it "responds to head requests for the landing page" do
    head "/"

    expect(last_response).to be_ok
    expect(last_response.body).to be_empty
  end

  it "serves public stylesheets" do
    get "/styles/site.css"

    expect(last_response).to be_ok
    expect(last_response.body).to include("--signal: #ff4b1f")
  end
end
