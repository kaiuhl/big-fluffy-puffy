require_relative "observation_freshness"

module BFP
  module FireRestrictions
    class Resolver
      SOURCE_PRECEDENCE = {
        "arcgis_feature_layer" => 100,
        "fs_fire_info_page" => 90,
        "fs_fire_page" => 88,
        "fs_alert_detail" => 85,
        "fs_alerts_page" => 80,
        "fs_release_page" => 70,
        "nps_fire_page" => 88,
        "nps_alerts_api" => 84,
        "nps_conditions_page" => 82,
        "partner_page" => 60,
        "state_feature_layer" => 40,
        "inciweb_feed" => 10,
        "nifc_feature_layer" => 10
      }.freeze

      def initialize(observation_freshness: ObservationFreshness.new)
        @observation_freshness = observation_freshness
      end

      def resolve(land_unit)
        land_unit = LandUnit[land_unit] unless land_unit.is_a?(LandUnit)
        return unless land_unit

        candidates = accepted_candidates(land_unit)
        observation = candidates.max_by { |candidate| candidate_sort_key(candidate) }
        status = status_record(land_unit)

        if observation.nil?
          publish_unknown(status, land_unit)
        elsif conflicting?(candidates)
          publish_conflict(status, land_unit, candidates)
        else
          publish_observation(status, land_unit, observation)
        end
      end

      private

      def accepted_candidates(land_unit)
        RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: %w[accepted auto_accepted])
          .where(Sequel.|({scope: nil}, {scope: "forestwide"}))
          .all
          .select { |candidate| @observation_freshness.current?(candidate) }
      end

      def conflicting?(candidates)
        statuses = candidates.filter_map { |candidate| candidate.status unless candidate.status == "unknown" }.uniq
        statuses.length > 1
      end

      def publish_unknown(status, land_unit)
        status.set(
          land_unit_id: land_unit.id,
          restriction_observation_id: nil,
          status: "unknown",
          campfire_policy: "unknown",
          confidence: 0.0,
          review_status: "needs_review",
          summary: "No accepted fire restriction observation is available yet.",
          evidence_quotes: Jsonb.wrap([]),
          last_checked_at: latest_checked_at(land_unit),
          updated_at: Time.now
        )
        status.save
      end

      def publish_conflict(status, land_unit, candidates)
        status.set(
          land_unit_id: land_unit.id,
          restriction_observation_id: nil,
          status: "unknown",
          campfire_policy: "unknown",
          confidence: 0.0,
          review_status: "needs_review",
          summary: "Accepted sources conflict; human review is required before publishing a status.",
          evidence_quotes: Jsonb.wrap(conflict_evidence(candidates)),
          last_checked_at: latest_checked_at(land_unit),
          updated_at: Time.now
        )
        status.save
      end

      def publish_observation(status, land_unit, observation)
        status.set(
          land_unit_id: land_unit.id,
          restriction_observation_id: observation.id,
          status: observation.status,
          campfire_policy: observation.campfire_policy,
          fire_danger_rating: observation.fire_danger_rating,
          ifpl_level: observation.ifpl_level,
          effective_start: observation.effective_start,
          effective_end: observation.effective_end,
          order_number: observation.order_number,
          affected_area: observation.affected_area,
          geometry_json: Jsonb.wrap(observation.geometry_json),
          summary: observation.summary,
          evidence_quotes: Jsonb.wrap(observation.evidence_quotes || []),
          confidence: observation.confidence,
          review_status: observation.review_status,
          source_url: observation.source_url,
          source_title: observation.source_title,
          last_checked_at: latest_checked_at(land_unit),
          published_at: Time.now,
          updated_at: Time.now
        )
        status.save
      end

      def status_record(land_unit)
        RestrictionStatus.first(land_unit_id: land_unit.id) ||
          RestrictionStatus.new(land_unit_id: land_unit.id, created_at: Time.now)
      end

      def latest_checked_at(land_unit)
        SourceFetch
          .join(:restriction_sources, id: :restriction_source_id)
          .where(Sequel[:restriction_sources][:land_unit_id] => land_unit.id)
          .max(Sequel[:source_fetches][:fetched_at])
      end

      def candidate_sort_key(candidate)
        source = candidate.restriction_source
        [
          SOURCE_PRECEDENCE.fetch(source.source_type, 0),
          candidate.confidence.to_f,
          candidate.created_at
        ]
      end

      def conflict_evidence(candidates)
        candidates.first(4).map do |candidate|
          "#{candidate.restriction_source.name}: #{candidate.status}"
        end
      end
    end
  end
end
