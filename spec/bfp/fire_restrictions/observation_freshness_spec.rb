require_relative "../../spec_helper"
require_relative "../../../lib/bfp/fire_restrictions/observation_freshness"

RSpec.describe BFP::FireRestrictions::ObservationFreshness do
  let(:now) { Time.utc(2026, 5, 31, 12, 0, 0) }
  let(:freshness) { described_class.new(now: now) }

  it "keeps an old accepted observation current when the latest successful fetch has the same hash" do
    observed_fetch = fetch(content_hash: "same", fetched_at: now - (20 * 24 * 60 * 60))
    latest_fetch = fetch(content_hash: "same", fetched_at: now - (7 * 24 * 60 * 60))
    observation = observation(source_fetch: observed_fetch, latest_fetches: [latest_fetch], created_at: now - (40 * 24 * 60 * 60))

    expect(freshness.current?(observation)).to be(true)
  end

  it "stales an accepted observation when the latest successful fetch has a different hash" do
    observed_fetch = fetch(content_hash: "old", fetched_at: now - (20 * 24 * 60 * 60))
    latest_fetch = fetch(content_hash: "new", fetched_at: now - (7 * 24 * 60 * 60))
    observation = observation(source_fetch: observed_fetch, latest_fetches: [latest_fetch], created_at: now - (20 * 24 * 60 * 60))

    expect(freshness.current?(observation)).to be(false)
  end

  it "stales an accepted observation when the source has not been successfully checked recently" do
    observed_fetch = fetch(content_hash: "same", fetched_at: now - (40 * 24 * 60 * 60))
    latest_fetch = fetch(content_hash: "same", fetched_at: now - (31 * 24 * 60 * 60))
    observation = observation(source_fetch: observed_fetch, latest_fetches: [latest_fetch], created_at: now - (40 * 24 * 60 * 60))

    expect(freshness.current?(observation)).to be(false)
  end

  it "falls back to observation age when there is no source fetch hash" do
    recent_observation = observation(source_fetch: nil, latest_fetches: [], created_at: now - (7 * 24 * 60 * 60))
    old_observation = observation(source_fetch: nil, latest_fetches: [], created_at: now - (31 * 24 * 60 * 60))

    expect(freshness.current?(recent_observation)).to be(true)
    expect(freshness.current?(old_observation)).to be(false)
  end

  def observation(source_fetch:, latest_fetches:, created_at:)
    source = Struct.new(:source_fetches_dataset).new(fetch_dataset(latest_fetches))
    Struct.new(:source_fetch, :restriction_source, :created_at).new(source_fetch, source, created_at)
  end

  def fetch(content_hash:, fetched_at:)
    Struct.new(:content_hash, :fetched_at).new(content_hash, fetched_at)
  end

  def fetch_dataset(fetches)
    dataset_class = Class.new do
      define_method(:initialize) { |rows| @rows = rows }
      define_method(:exclude) { |_conditions| self }
      define_method(:reverse) { |_column| self }
      define_method(:first) { @rows.first }
    end

    dataset_class.new(fetches)
  end
end
