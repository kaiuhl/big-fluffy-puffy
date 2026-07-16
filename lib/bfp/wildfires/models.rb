require "sequel/extensions/pg_json"

module BFP
  module Wildfires
    BFP.db.extension :pg_json
    Sequel::Model.db = BFP.db

    class WildfireIncident < Sequel::Model(:wildfire_incidents)
      def self.active_set
        where(active: true).order(:irwin_id).all
      end

      def perimeter_geometry
        perimeter_geometry_json&.to_hash || perimeter_geometry_json
      end

      def attributes
        attributes_json&.to_hash || attributes_json || {}
      end
    end

    class WildfireSync < Sequel::Model(:wildfire_syncs)
      def self.last_successful
        where(success: true).exclude(finished_at: nil).order(Sequel.desc(:finished_at)).first
      end
    end
  end
end
