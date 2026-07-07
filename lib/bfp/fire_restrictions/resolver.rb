require_relative "observation_freshness"
require_relative "localized_rule_resolver"
require_relative "status_display"
require "date"

module BFP
  module FireRestrictions
    class Resolver
      PUBLISHABLE_SCOPES = %w[forestwide mixed].freeze
      LOCALIZED_POLICY_PRECEDENCE = %w[
        prohibited
        stoves_only
        developed_sites_only
        fire_pan_required
        propane_allowed
        allowed
        unknown
      ].freeze
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

      def initialize(observation_freshness: ObservationFreshness.new, localized_rule_resolver: LocalizedRuleResolver.new, today: Date.today)
        @observation_freshness = observation_freshness
        @localized_rule_resolver = localized_rule_resolver
        @today = today
      end

      def resolve(land_unit)
        land_unit = LandUnit[land_unit] unless land_unit.is_a?(LandUnit)
        return unless land_unit

        candidates = accepted_candidates(land_unit)
        observation = candidates.max_by { |candidate| candidate_sort_key(candidate) }
        status = status_record(land_unit)
        previous = status.new? ? nil : {status: status.status, campfire_policy: status.campfire_policy}

        if observation.nil?
          localized_rules = @localized_rule_resolver.active_rules_for(land_unit, on: @today)
          if localized_rules.any?
            publish_localized_status(status, land_unit, localized_rules)
          else
            publish_unknown(status, land_unit)
          end
        elsif conflicting?(candidates)
          publish_conflict(status, land_unit, candidates)
        else
          publish_observation(status, land_unit, observation)
        end

        record_status_change(land_unit, status, previous)
        status
      end

      private

      def accepted_candidates(land_unit)
        RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: %w[accepted auto_accepted])
          .where(Sequel.|({scope: nil}, {scope: PUBLISHABLE_SCOPES}))
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

      def publish_localized_status(status, land_unit, rules)
        status.set(
          land_unit_id: land_unit.id,
          restriction_observation_id: nil,
          status: "partial",
          campfire_policy: localized_campfire_policy(rules),
          fire_danger_rating: nil,
          ifpl_level: nil,
          effective_start: nil,
          effective_end: nil,
          order_number: nil,
          affected_area: localized_affected_area(rules),
          geometry_json: Jsonb.wrap(nil),
          summary: localized_summary(rules),
          evidence_quotes: Jsonb.wrap(localized_evidence(rules)),
          confidence: rules.map { |rule| rule.confidence.to_f }.max || 0.0,
          review_status: "accepted",
          source_url: rules.first&.source_url,
          source_title: "Accepted localized fire-use rules",
          last_checked_at: latest_checked_at(land_unit),
          published_at: Time.now,
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

      # Appends to the public change log whenever the published status
      # or the effective campfire answer transitions. Raw campfire_policy
      # flaps that do not change the public meaning (for example
      # none/unknown to none/allowed) are not logged. A from-less entry
      # marks the first published status for a land unit.
      def record_status_change(land_unit, status, previous)
        return if previous && previous[:status] == status.status &&
          effective_campfire_policy(previous[:status], previous[:campfire_policy]) ==
            effective_campfire_policy(status.status, status.campfire_policy)

        RestrictionStatusChange.create(
          land_unit_id: land_unit.id,
          restriction_observation_id: status.restriction_observation_id,
          from_status: previous && previous[:status],
          from_campfire_policy: previous && previous[:campfire_policy],
          to_status: status.status,
          to_campfire_policy: status.campfire_policy,
          summary: status.summary,
          source_url: status.source_url,
          source_title: status.source_title,
          order_number: status.order_number,
          effective_start: status.effective_start,
          effective_end: status.effective_end,
          changed_at: Time.now
        )
      end

      def effective_campfire_policy(status_value, campfire_policy)
        StatusDisplay.campfire_policy(status: status_value, campfire_policy: campfire_policy)
      end

      def latest_checked_at(land_unit)
        SourceFetch
          .join(:restriction_sources, id: :restriction_source_id)
          .where(Sequel[:restriction_sources][:land_unit_id] => land_unit.id)
          .max(Sequel[:source_fetches][:fetched_at])
      end

      def localized_campfire_policy(rules)
        policies = rules.map { |rule| rule.campfire_policy.to_s.empty? ? "unknown" : rule.campfire_policy.to_s }
        LOCALIZED_POLICY_PRECEDENCE.find { |policy| policies.include?(policy) } || "unknown"
      end

      def localized_affected_area(rules)
        titles = rules.first(3).map(&:title)
        suffix = (rules.length > titles.length) ? " and #{rules.length - titles.length} more" : nil

        (titles + [suffix]).compact.join(", ")
      end

      def localized_summary(rules)
        if rules.length == 1
          "Accepted localized fire-use restriction is active: #{rules.first.title}."
        else
          "Accepted localized fire-use restrictions are active, including #{localized_affected_area(rules)}."
        end
      end

      def localized_evidence(rules)
        rules.flat_map { |rule| Array(rule.evidence_quotes) }.compact.map(&:to_s).reject(&:empty?).uniq.first(4)
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
