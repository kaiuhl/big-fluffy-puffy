module BFP
  module FireRestrictions
    class Poller
      def initialize(fetcher: Fetcher.new, parser: SourceParser.new)
        @fetcher = fetcher
        @parser = parser
      end

      def poll_due(limit: 25)
        sources_due(limit: limit).map { |source| poll(source) }
      end

      def poll_source_slug(slug)
        source = RestrictionSource.first(slug: slug)
        raise "Unknown fire restriction source: #{slug}" unless source

        poll(source)
      end

      def poll(source)
        source = RestrictionSource[source] unless source.is_a?(RestrictionSource)
        fetch = @fetcher.fetch_source(source)

        if parse_fetch?(fetch)
          @parser.parse_fetch(fetch)
        else
          Resolver.new.resolve(source.land_unit)
        end

        fetch
      end

      private

      def sources_due(limit:)
        RestrictionSource
          .where(active: true)
          .order(Sequel.asc(:last_checked_at, nulls: :first), :id)
          .all
          .select(&:due?)
          .first(limit)
      end

      def parse_fetch?(fetch)
        return false if fetch.error_class
        return false unless fetch.source_document

        fetch.content_changed ||
          RestrictionObservation.where(source_fetch_id: fetch.id).empty? &&
            RestrictionObservation.where(restriction_source_id: fetch.restriction_source_id).empty?
      end
    end
  end
end
