require "sequel/extensions/pg_json"

module BFP
  module Places
    BFP.db.extension :pg_json
    Sequel::Model.db = BFP.db

    module Jsonb
      def self.wrap(value)
        return if value.nil?
        return value if value.is_a?(Sequel::Postgres::JSONBObject)

        Sequel.pg_jsonb(value)
      end
    end

    class PlaceDataset < Sequel::Model(:place_datasets)
      one_to_many :places, key: :source_dataset_id

      def metadata
        metadata_json || {}
      end
    end

    class Place < Sequel::Model(:places)
      many_to_one :source_dataset, class: "BFP::Places::PlaceDataset", key: :source_dataset_id
      one_to_many :place_names
      one_to_many :place_land_unit_matches
      one_to_many :place_localized_rule_matches

      def geometry
        geometry_json&.to_hash || geometry_json
      end

      def metadata
        metadata_json&.to_hash || metadata_json || {}
      end
    end

    class PlaceName < Sequel::Model(:place_names)
      many_to_one :place
    end

    class PlaceLandUnitMatch < Sequel::Model(:place_land_unit_matches)
      many_to_one :place
      many_to_one :land_unit, class: "BFP::FireRestrictions::LandUnit", key: :land_unit_id
    end

    class PlaceLocalizedRuleMatch < Sequel::Model(:place_localized_rule_matches)
      many_to_one :place
      many_to_one :localized_fire_use_rule, class: "BFP::FireRestrictions::LocalizedFireUseRule", key: :localized_fire_use_rule_id
    end
  end
end
