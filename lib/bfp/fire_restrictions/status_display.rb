require "date"
require "time"

module BFP
  module FireRestrictions
    module StatusDisplay
      module_function

      def campfire_policy(status:, campfire_policy:)
        policy = campfire_policy.to_s
        return "allowed" if status.to_s == "none" && (policy.empty? || policy == "unknown")

        policy.empty? ? "unknown" : policy
      end

      def checked_date_label(value)
        Time.iso8601(value.to_s).utc.strftime("%b %-d, %Y")
      rescue ArgumentError
        "checked"
      end

      def policy_label(value)
        case value.to_s.empty? ? "unknown" : value.to_s
        when "fire_pan_required"
          "Fire pan required"
        else
          labelize(value.to_s.empty? ? "unknown" : value.to_s)
        end
      end

      def stove_policy_label(value, shutoff_required: nil)
        policy = value.to_s.empty? ? "unknown" : value.to_s
        label = case policy
        when "allowed_with_shutoff_valve"
          "Allowed with shutoff valve"
        when "developed_sites_only"
          "Developed sites only"
        when "fire_pan_required"
          "Fire pan required"
        else
          labelize(policy)
        end

        if shutoff_required == true && !label.downcase.include?("shutoff")
          "#{label}; shutoff valve required"
        else
          label
        end
      end

      def duration_label(rule)
        duration_type = rule.fetch(:duration_type, "unknown").to_s

        case duration_type
        when "permanent"
          "Permanent"
        when "seasonal"
          season = [rule[:season_start], rule[:season_end]].compact.join(" to ")
          season.empty? ? "Seasonal" : "Seasonal #{season}"
        when "temporary"
          date_range_label(rule[:effective_start], rule[:effective_end])
        when "incident"
          "Incident"
        else
          date_range_label(rule[:effective_start], rule[:effective_end])
        end
      end

      def date_range_label(start_value, end_value)
        start_label = date_only_label(start_value)
        end_label = date_only_label(end_value)

        if start_label && end_label
          "#{start_label} to #{end_label}"
        elsif start_label
          "Since #{start_label}"
        elsif end_label
          "Through #{end_label}"
        else
          "Current"
        end
      end

      def labelize(value)
        value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
      end

      def date_only_label(value)
        return if value.to_s.empty?

        Date.parse(value.to_s).strftime("%b %-d, %Y")
      rescue ArgumentError
        nil
      end
    end
  end
end
