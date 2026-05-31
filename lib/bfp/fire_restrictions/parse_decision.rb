module BFP
  module FireRestrictions
    class ParseDecision
      def self.parse_fetch?(fetch, observation_model: nil)
        return false if fetch.error_class
        return false unless fetch.source_document
        return true if fetch.content_changed

        observation_model ||= RestrictionObservation
        return false unless observation_model.where(source_fetch_id: fetch.id).empty?

        source_observations = observation_model.where(restriction_source_id: fetch.restriction_source_id)
        return true if source_observations.empty?

        llm_parse_enabled? && source_observations.all? { |observation| placeholder_observation?(observation) }
      end

      def self.llm_parse_enabled?
        ENV.fetch("LLM_PARSE_ENABLED", "false") == "true"
      end

      def self.placeholder_observation?(observation)
        Array(observation.needs_review_reasons).any? do |reason|
          reason.to_s.match?(/LLM parsing is disabled or unavailable/i)
        end
      end
    end
  end
end
