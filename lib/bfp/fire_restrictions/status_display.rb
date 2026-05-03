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
    end
  end
end
