require "sequel/extensions/pg_json"
require "bfp/fire_restrictions/models"

module BFP
  module Climate
    BFP.db.extension :pg_json
    Sequel::Model.db = BFP.db

    class Dataset < Sequel::Model(:climate_datasets)
      one_to_many :land_unit_normals, class: "BFP::Climate::LandUnitNormal", key: :climate_dataset_id

      def metadata
        metadata_json || {}
      end
    end

    class LandUnitNormal < Sequel::Model(:land_unit_climate_normals)
      many_to_one :dataset, class: "BFP::Climate::Dataset", key: :climate_dataset_id
      many_to_one :land_unit, class: "BFP::FireRestrictions::LandUnit", key: :land_unit_id

      def metadata
        metadata_json || {}
      end
    end
  end
end

BFP::FireRestrictions::LandUnit.one_to_many(
  :climate_normals,
  class: "BFP::Climate::LandUnitNormal",
  key: :land_unit_id
)
