module BFP
  module FireRestrictions
    Sequel::Model.db = BFP.db

    class LandUnit < Sequel::Model(:land_units)
      one_to_many :restriction_sources
      one_to_many :restriction_observations
      one_to_one :restriction_status

      def metadata_sources
        restriction_sources_dataset.where(active: true).order(:name).all
      end
    end

    class RestrictionSource < Sequel::Model(:restriction_sources)
      many_to_one :land_unit
      one_to_many :source_fetches
      one_to_many :restriction_observations

      def due?(now = Time.now)
        return true unless last_checked_at

        last_checked_at <= now - (poll_interval_minutes * 60)
      end

      def metadata
        metadata_json || {}
      end
    end

    class SourceDocument < Sequel::Model(:source_documents)
      one_to_many :source_fetches
    end

    class SourceFetch < Sequel::Model(:source_fetches)
      many_to_one :restriction_source
      many_to_one :source_document
    end

    class RestrictionObservation < Sequel::Model(:restriction_observations)
      many_to_one :land_unit
      many_to_one :restriction_source
      many_to_one :source_fetch
      one_to_one :restriction_status

      def needs_review?
        review_status == "needs_review"
      end
    end

    class RestrictionStatus < Sequel::Model(:restriction_statuses)
      many_to_one :land_unit
      many_to_one :restriction_observation
    end
  end
end
