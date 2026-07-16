require_relative "../../../config/boot"
require_relative "../../spec_helper"

# Loading the trip-check presenter transitively opens a database connection, so
# this suite is gated like the other DB integration specs even though the
# wildfire error-safety assertions themselves stub the collaborators.
RSpec.describe "BFP::Places::TripCheckPresenter wildfire integration", :db do
  before do
    skip "Set RUN_DB_SPECS=true with TEST_DATABASE_URL to run database integration specs." unless ENV["RUN_DB_SPECS"] == "true"
    require "bfp/places/trip_check_presenter"
  end

  let(:presenter) { BFP::Places::TripCheckPresenter.new }

  describe "wildfire context error safety" do
    it "returns nil when the place has no coordinates" do
      place = instance_double("place", latitude: nil, longitude: nil)

      expect(presenter.send(:wildfire_context, place)).to be_nil
    end

    it "yields nil when the wildfire library or table is unavailable" do
      place = instance_double("place", latitude: 44.0, longitude: -121.0)
      allow(presenter).to receive(:require).with("bfp/wildfires").and_raise(LoadError)

      expect(presenter.send(:wildfire_context, place)).to be_nil
    end

    it "yields nil on any wildfire failure so the trip check survives" do
      place = instance_double("place", latitude: 44.0, longitude: -121.0)
      allow(presenter).to receive(:require).with("bfp/wildfires").and_raise(Sequel::DatabaseError.new("missing table"))

      expect(presenter.send(:wildfire_context, place)).to be_nil
    end
  end

  describe "wildfire map feature error safety" do
    it "returns an empty array when wildfire features cannot be built" do
      allow(presenter).to receive(:require).with("bfp/wildfires").and_raise(StandardError.new("down"))

      expect(presenter.send(:wildfire_map_features, 44.0, -121.0)).to eq([])
    end
  end
end
