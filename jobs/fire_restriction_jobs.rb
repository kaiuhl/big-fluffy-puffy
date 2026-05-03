require_relative "../config/boot"
require "bfp/fire_restrictions"

module BFP
  module FireRestrictions
    class PollDueSourcesJob < Que::Job
      def self.perform_now(limit: 25)
        RestrictionSource
          .where(active: true)
          .order(Sequel.asc(:last_checked_at, nulls: :first), :id)
          .all
          .select(&:due?)
          .first(limit)
          .each { |source| FetchSourceJob.enqueue(source.slug) }
      end

      def run(limit = 25)
        self.class.perform_now(limit: limit)
      end
    end

    class FetchSourceJob < Que::Job
      def self.perform_now(source_slug)
        source = RestrictionSource.first(slug: source_slug)
        raise "Unknown fire restriction source: #{source_slug}" unless source

        fetch = Fetcher.new.fetch_source(source)
        if parse_fetch?(fetch)
          ParseSourceFetchJob.enqueue(fetch.id)
        else
          ResolveLandUnitStatusJob.enqueue(source.land_unit.slug)
        end
        fetch
      end

      def self.parse_fetch?(fetch)
        return false if fetch.error_class
        return false unless fetch.source_document

        fetch.content_changed ||
          RestrictionObservation.where(source_fetch_id: fetch.id).empty? &&
            RestrictionObservation.where(restriction_source_id: fetch.restriction_source_id).empty?
      end

      def run(source_slug)
        self.class.perform_now(source_slug)
      end
    end

    class ParseSourceFetchJob < Que::Job
      def self.perform_now(source_fetch_id)
        fetch = SourceFetch[source_fetch_id]
        raise "Unknown source fetch: #{source_fetch_id}" unless fetch

        SourceParser.new.parse_fetch(fetch)
      end

      def run(source_fetch_id)
        self.class.perform_now(source_fetch_id)
      end
    end

    class ResolveLandUnitStatusJob < Que::Job
      def self.perform_now(land_unit_slug)
        land_unit = LandUnit.first(slug: land_unit_slug)
        raise "Unknown land unit: #{land_unit_slug}" unless land_unit

        Resolver.new.resolve(land_unit)
      end

      def run(land_unit_slug)
        self.class.perform_now(land_unit_slug)
      end
    end
  end
end
