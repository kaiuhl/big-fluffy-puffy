require_relative "models"
require_relative "resolver"
require_relative "status_display"

module BFP
  module FireRestrictions
    # Reconstructs change-log history from the archive of accepted
    # observations, for land units whose statuses predate live change
    # recording. Reconstructed entries carry origin "backfill" and are
    # labeled publicly; re-running deletes and rebuilds them, and never
    # touches live resolver-recorded entries.
    class ChangeLogBackfill
      ORIGIN = "backfill".freeze

      def run
        counts = {land_units: 0, entries: 0}

        LandUnit.order(:slug).each do |land_unit|
          entries = rebuild_land_unit(land_unit)
          counts[:land_units] += 1 if entries.positive?
          counts[:entries] += entries
        end

        counts
      end

      private

      def rebuild_land_unit(land_unit)
        RestrictionStatusChange.where(land_unit_id: land_unit.id, origin: ORIGIN).delete

        live_boundary = RestrictionStatusChange
          .where(land_unit_id: land_unit.id)
          .min(:changed_at)

        previous = nil
        created = 0

        accepted_observations(land_unit, before: live_boundary).each do |observation|
          pair = effective_pair(observation.status, observation.campfire_policy)
          next if previous == pair

          create_entry(land_unit, observation, previous)
          previous = pair
          created += 1
        end

        created + reconcile_with_current_status(land_unit, previous, live_boundary)
      end

      # Compares the public meaning, not raw stored values, so a
      # campfire_policy flap like none/unknown to none/allowed does not
      # produce a visible non-change entry.
      def effective_pair(status_value, campfire_policy)
        [status_value, StatusDisplay.campfire_policy(status: status_value, campfire_policy: campfire_policy)]
      end

      def accepted_observations(land_unit, before:)
        dataset = RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: %w[accepted auto_accepted])
          .where(Sequel.|({scope: nil}, {scope: Resolver::PUBLISHABLE_SCOPES}))
          .order(:created_at, :id)
        dataset = dataset.where { created_at < before } if before
        dataset.all
      end

      def create_entry(land_unit, observation, previous)
        RestrictionStatusChange.create(
          land_unit_id: land_unit.id,
          restriction_observation_id: observation.id,
          from_status: previous && previous[0],
          from_campfire_policy: previous && previous[1],
          to_status: observation.status,
          to_campfire_policy: observation.campfire_policy,
          summary: observation.summary,
          source_url: observation.source_url,
          source_title: observation.source_title,
          order_number: observation.order_number,
          effective_start: observation.effective_start,
          effective_end: observation.effective_end,
          changed_at: observation.created_at,
          origin: ORIGIN
        )
      end

      # Closes the chain between the replayed archive and the currently
      # published status, so future live entries connect cleanly. Skipped
      # when live entries already continue the chain, and for units whose
      # only reconstructable event would be a lone "unknown".
      def reconcile_with_current_status(land_unit, previous, live_boundary)
        return 0 if live_boundary

        status = RestrictionStatus.first(land_unit_id: land_unit.id)
        return 0 unless status
        return 0 if previous.nil? && status.status == "unknown"

        pair = effective_pair(status.status, status.campfire_policy)
        return 0 if previous == pair

        RestrictionStatusChange.create(
          land_unit_id: land_unit.id,
          restriction_observation_id: status.restriction_observation_id,
          from_status: previous && previous[0],
          from_campfire_policy: previous && previous[1],
          to_status: status.status,
          to_campfire_policy: status.campfire_policy,
          summary: status.summary,
          source_url: status.source_url,
          source_title: status.source_title,
          order_number: status.order_number,
          effective_start: status.effective_start,
          effective_end: status.effective_end,
          changed_at: status.published_at || status.updated_at || Time.now,
          origin: ORIGIN
        )
        1
      end
    end
  end
end
