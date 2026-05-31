module BFP
  module FireRestrictions
    class ParseDecision
      def self.parse_fetch?(fetch, observation_model: nil)
        return false if fetch.error_class
        return false unless fetch.source_document
        return true if fetch.content_changed

        observation_model ||= RestrictionObservation
        observation_model.where(source_fetch_id: fetch.id).empty? &&
          observation_model.where(restriction_source_id: fetch.restriction_source_id).empty?
      end
    end
  end
end
