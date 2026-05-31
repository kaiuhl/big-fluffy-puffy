module BFP
  module FireRestrictions
    class ObservationFreshness
      DEFAULT_MAX_AGE_SECONDS = 30 * 24 * 60 * 60

      def initialize(now: nil, max_age_seconds: DEFAULT_MAX_AGE_SECONDS)
        @now = now || Time.now
        @max_age_seconds = max_age_seconds
      end

      def current?(observation)
        observed_fetch = observation.source_fetch
        return recent?(observation.created_at) unless observed_fetch&.content_hash

        latest_fetch = latest_successful_fetch(observation.restriction_source)
        return false unless latest_fetch&.fetched_at
        return false unless recent?(latest_fetch.fetched_at)

        latest_fetch.content_hash == observed_fetch.content_hash
      end

      private

      def latest_successful_fetch(source)
        source
          &.source_fetches_dataset
          &.exclude(content_hash: nil)
          &.reverse(:fetched_at)
          &.first
      end

      def recent?(time)
        return false unless time

        time > @now - @max_age_seconds
      end
    end
  end
end
