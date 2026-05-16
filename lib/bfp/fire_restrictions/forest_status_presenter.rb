require "date"
require_relative "localized_rule_resolver"
require_relative "status_display"
require_relative "status_presenter"

module BFP
  module FireRestrictions
    class ForestStatusPresenter
      def initialize(month: Date.today.month, on: Date.today, status_presenter: StatusPresenter.new(month: month), rule_resolver: LocalizedRuleResolver.new)
        @on = on
        @status_presenter = status_presenter
        @rule_resolver = rule_resolver
      end

      def forest(slug)
        land_unit = LandUnit.first(slug: slug.to_s, active: true)
        return unless land_unit

        forest = @status_presenter.forest(slug)
        return unless forest

        {
          forest: forest,
          localized_restrictions: localized_restrictions(land_unit),
          map_endpoint: "/api/fire-restrictions/forests/#{land_unit.slug}/map"
        }
      rescue Sequel::DatabaseError
        nil
      end

      private

      def localized_restrictions(land_unit)
        @rule_resolver.active_rules_for(land_unit, on: @on).map { |rule| serialize_rule(rule) }
      end

      def serialize_rule(rule)
        area = rule.restriction_area
        source = rule.restriction_source
        fetch = rule.source_fetch
        geometry = rule.geometry_json || area&.geometry_json
        geometry_source_type = rule.geometry_source_type || area&.geometry_source_type || "none"

        {
          id: rule.id,
          slug: rule.slug,
          title: rule.title,
          status: rule.status,
          duration_type: rule.duration_type,
          group: group_for(rule),
          campfire_policy: policy_value(rule.campfire_policy),
          charcoal_policy: policy_value(rule.charcoal_policy),
          gas_stove_policy: policy_value(rule.gas_stove_policy),
          liquid_fuel_stove_policy: policy_value(rule.liquid_fuel_stove_policy),
          alcohol_stove_policy: policy_value(rule.alcohol_stove_policy),
          solid_fuel_stove_policy: policy_value(rule.solid_fuel_stove_policy),
          wood_stove_policy: policy_value(rule.wood_stove_policy),
          stove_shutoff_valve_required: rule.stove_shutoff_valve_required,
          effective_start: rule.effective_start&.iso8601,
          effective_end: rule.effective_end&.iso8601,
          season_start: season_date(rule.season_start_month, rule.season_start_day),
          season_end: season_date(rule.season_end_month, rule.season_end_day),
          incident_name: rule.incident_name,
          incident_number: rule.incident_number,
          affected_area: rule.affected_area || area&.name,
          area: serialize_area(area),
          summary: rule.summary,
          evidence_quotes: json_array(rule.evidence_quotes),
          confidence: rule.confidence.to_f,
          review_status: rule.review_status,
          last_checked_at: fetch&.fetched_at&.iso8601,
          source_url: rule.source_url || source&.url,
          source_title: rule.source_title || source&.name,
          geometry_json: geometry,
          mapped: geojson_geometry?(geometry),
          geometry_source_type: geometry_source_type,
          geometry_provenance: area&.geometry_provenance_json || {},
          next_review_due_on: rule.next_review_due_on&.iso8601
        }
      end

      def serialize_area(area)
        return unless area

        {
          slug: area.slug,
          name: area.name,
          area_type: area.area_type,
          description: area.area_description,
          geometry_source_type: area.geometry_source_type,
          geometry_source_url: area.geometry_source_url
        }
      end

      def group_for(rule)
        (rule.duration_type.to_s == "permanent") ? "permanent" : "current"
      end

      def season_date(month, day)
        return unless month && day

        format("%02d-%02d", month, day)
      end

      def policy_value(value)
        value.to_s.empty? ? "unknown" : value.to_s
      end

      def geojson_geometry?(geometry)
        geometry.is_a?(Hash) &&
          (geometry["type"] || geometry[:type]).to_s != "" &&
          (geometry["coordinates"] || geometry[:coordinates])
      end

      def json_array(value)
        return [] if value.nil?
        return value if value.is_a?(Array)
        return value.to_a if value.respond_to?(:to_a)

        [value]
      end
    end
  end
end
