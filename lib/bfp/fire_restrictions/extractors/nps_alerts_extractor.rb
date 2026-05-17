require "json"
require "time"

module BFP
  module FireRestrictions
    module Extractors
      class NpsAlertsExtractor
        FIRE_PATTERN = /fire|campfire|camp fire|burn ban|fire ban|charcoal|stove|wildfire|smoke/i

        def extract(body, final_url: nil)
          data = JSON.parse(body.to_s)
          alerts = Array(data["data"])
          fire_alerts = alerts.select { |alert| fire_alert?(alert) }

          {
            title: "NPS alerts",
            canonical_url: final_url,
            modified_at: latest_modified_at(alerts),
            extracted_text: extracted_text(alerts, fire_alerts, final_url),
            extraction_status: "ok",
            metadata_json: {
              nps_alert_count: alerts.length,
              nps_fire_alert_count: fire_alerts.length,
              nps_fire_alert_titles: fire_alerts.map { |alert| alert["title"].to_s }.reject(&:empty?).first(40)
            }
          }
        rescue JSON::ParserError => error
          {
            title: "NPS alerts",
            canonical_url: final_url,
            extracted_text: "",
            extraction_status: "needs_review",
            extraction_error: "NPS alerts response was not valid JSON: #{error.message}",
            metadata_json: {}
          }
        end

        private

        def extracted_text(alerts, fire_alerts, final_url)
          lines = []
          lines << "Title: NPS alerts"
          lines << "Canonical URL: #{final_url}" if final_url
          lines << "NPS Alert Summary:"
          lines << "Active NPS alerts returned: #{alerts.length}"
          if fire_alerts.empty?
            lines << "No fire-related NPS alerts were returned by the NPS alerts API."
          else
            lines << "Fire-related NPS alerts returned:"
            fire_alerts.each { |alert| lines << alert_line(alert) }
          end
          lines.join("\n")
        end

        def alert_line(alert)
          [
            text(alert["title"]),
            ("Category: #{text(alert["category"])}" if present?(alert["category"])),
            ("Park: #{Array(alert["parkCode"]).join(", ")}" unless Array(alert["parkCode"]).empty?),
            text(alert["description"]),
            text(alert["url"])
          ].compact.reject(&:empty?).join(" | ")[0, 1600]
        end

        def fire_alert?(alert)
          [
            alert["title"],
            alert["description"],
            alert["category"],
            alert["url"]
          ].compact.join(" ").match?(FIRE_PATTERN)
        end

        def latest_modified_at(alerts)
          alerts
            .filter_map { |alert| parse_time(alert["lastIndexedDate"] || alert["lastUpdated"]) }
            .max
        end

        def parse_time(value)
          return if value.to_s.strip.empty?

          Time.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def text(value)
          value.to_s.tr("\u00a0", " ").gsub(/\s+/, " ").strip
        end

        def present?(value)
          !text(value).empty?
        end
      end
    end
  end
end
