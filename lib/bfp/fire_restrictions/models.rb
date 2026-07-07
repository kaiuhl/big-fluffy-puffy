require "sequel/extensions/pg_json"

module BFP
  module FireRestrictions
    BFP.db.extension :pg_json
    Sequel::Model.db = BFP.db

    module Jsonb
      def self.wrap(value)
        return if value.nil?
        return value if value.is_a?(Sequel::Postgres::JSONBObject)

        Sequel.pg_jsonb(value)
      end
    end

    class LandUnit < Sequel::Model(:land_units)
      one_to_many :restriction_sources
      one_to_many :restriction_areas
      one_to_many :restriction_observations
      one_to_many :localized_fire_use_rules
      one_to_one :restriction_status

      def metadata_sources
        restriction_sources_dataset.where(active: true).order(:name).all
      end
    end

    class RestrictionSource < Sequel::Model(:restriction_sources)
      many_to_one :land_unit
      one_to_many :source_fetches
      one_to_many :restriction_observations
      one_to_many :localized_fire_use_rules

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
      one_to_many :localized_fire_use_rules
    end

    class RestrictionArea < Sequel::Model(:restriction_areas)
      many_to_one :land_unit
      one_to_many :localized_fire_use_rules
    end

    class RestrictionObservation < Sequel::Model(:restriction_observations)
      many_to_one :land_unit
      many_to_one :restriction_source
      many_to_one :source_fetch
      one_to_one :restriction_status
      one_to_many :localized_fire_use_rules

      def needs_review?
        review_status == "needs_review"
      end
    end

    class LocalizedFireUseRule < Sequel::Model(:localized_fire_use_rules)
      many_to_one :land_unit
      many_to_one :restriction_area
      many_to_one :restriction_observation
      many_to_one :restriction_source
      many_to_one :source_fetch
      many_to_one :supersedes_rule, class: "BFP::FireRestrictions::LocalizedFireUseRule", key: :supersedes_rule_id
      one_to_many :superseded_rules, class: "BFP::FireRestrictions::LocalizedFireUseRule", key: :supersedes_rule_id
    end

    class RestrictionStatus < Sequel::Model(:restriction_statuses)
      many_to_one :land_unit
      many_to_one :restriction_observation
    end

    class RestrictionStatusChange < Sequel::Model(:restriction_status_changes)
      many_to_one :land_unit
      many_to_one :restriction_observation
    end
  end
end
