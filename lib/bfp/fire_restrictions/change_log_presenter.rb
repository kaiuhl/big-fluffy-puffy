require_relative "models"
require_relative "status_display"

module BFP
  module FireRestrictions
    # Presents the public change log: published status transitions
    # recorded by the resolver, newest first, grouped by day.
    class ChangeLogPresenter
      DEFAULT_LIMIT = 150

      CAMPFIRE_SEVERITY = {
        "prohibited" => 4,
        "stoves_only" => 3,
        "fire_pan_required" => 3,
        "developed_sites_only" => 2,
        "allowed_with_shutoff_valve" => 1,
        "propane_allowed" => 1,
        "allowed" => 0
      }.freeze

      def initialize(limit: DEFAULT_LIMIT)
        @limit = limit
      end

      def entries
        RestrictionStatusChange
          .eager(:land_unit)
          .order(Sequel.desc(:changed_at), Sequel.desc(:id))
          .limit(@limit)
          .all
          .map { |change| entry(change) }
      end

      def day_groups
        entries
          .group_by { |entry| entry[:changed_on] }
          .map { |date, day_entries| {date: date, label: day_label(date), entries: day_entries} }
      end

      private

      def entry(change)
        unit = change.land_unit
        from_label, to_label = transition_labels(change)

        {
          id: change.id,
          slug: unit&.slug,
          name: unit&.name,
          land_unit_url: unit && "/fire-restrictions/#{unit.slug}",
          agency: unit&.agency,
          unit_type: unit&.unit_type,
          region_code: unit&.region_code,
          market_bucket: unit&.market_bucket,
          first_record: change.from_status.nil?,
          reconstructed: change.origin == "backfill",
          direction: direction(change),
          from_label: from_label,
          to_label: to_label,
          summary: change.summary,
          source_url: change.source_url,
          source_title: change.source_title,
          order_number: change.order_number,
          effective_start: change.effective_start&.iso8601,
          effective_end: change.effective_end&.iso8601,
          effective_label: effective_label(change),
          changed_at: change.changed_at&.iso8601,
          changed_on: change.changed_at&.strftime("%Y-%m-%d")
        }
      end

      def effective_label(change)
        dates = [change.effective_start, change.effective_end].compact
        return if dates.empty?

        dates.map { |date| date.strftime("%b %-d, %Y") }.join(" to ")
      end

      # Leads with the campfire answer; falls back to the raw status
      # words when the campfire answer did not move (for example
      # stage_1 -> stage_2, both prohibited).
      def transition_labels(change)
        from_policy = change.from_status && effective_policy(change.from_status, change.from_campfire_policy)
        to_policy = effective_policy(change.to_status, change.to_campfire_policy)

        if from_policy && from_policy == to_policy
          [status_label(change.from_status), status_label(change.to_status)]
        else
          [from_policy && policy_label(from_policy), policy_label(to_policy)]
        end
      end

      def direction(change)
        return "first" if change.from_status.nil?

        from = CAMPFIRE_SEVERITY[effective_policy(change.from_status, change.from_campfire_policy)]
        to = CAMPFIRE_SEVERITY[effective_policy(change.to_status, change.to_campfire_policy)]
        return "updated" unless from && to

        if to > from
          "tightened"
        elsif to < from
          "eased"
        else
          "updated"
        end
      end

      def effective_policy(status, campfire_policy)
        StatusDisplay.campfire_policy(status: status, campfire_policy: campfire_policy)
      end

      def policy_label(policy)
        case policy.to_s
        when "prohibited"
          "No campfires"
        when "developed_sites_only"
          "Developed sites only"
        when "allowed"
          "Campfires allowed"
        when "unknown", ""
          "Unknown"
        else
          StatusDisplay.policy_label(policy)
        end
      end

      def status_label(status)
        value = status.to_s.empty? ? "unknown" : status.to_s
        value.tr("_", " ").split.map(&:capitalize).join(" ")
      end

      def day_label(date)
        return "Undated" unless date

        Date.iso8601(date).strftime("%b %-d, %Y")
      end
    end
  end
end
