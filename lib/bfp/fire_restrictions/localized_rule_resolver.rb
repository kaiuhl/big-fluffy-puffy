require "date"

module BFP
  module FireRestrictions
    class LocalizedRuleResolver
      PUBLISHED_REVIEW_STATUSES = %w[accepted auto_accepted].freeze
      ACTIVE_STATUSES = %w[partial stage_1 stage_2 full closure year_round].freeze

      def active_rules_for(land_unit, on: Date.today)
        land_unit = resolve_land_unit(land_unit)
        return [] unless land_unit

        LocalizedFireUseRule
          .where(land_unit_id: land_unit.id, review_status: PUBLISHED_REVIEW_STATUSES)
          .where(superseded_at: nil)
          .all
          .select { |rule| active_rule?(rule, on: on) }
          .sort_by { |rule| sort_key(rule) }
      end

      private

      def resolve_land_unit(value)
        return value if value.is_a?(LandUnit)
        return LandUnit[value] if value.is_a?(Integer)

        LandUnit.first(slug: value.to_s)
      end

      def active_rule?(rule, on:)
        ACTIVE_STATUSES.include?(rule.status.to_s) && active_duration?(rule, on: on)
      end

      def active_duration?(rule, on:)
        case rule.duration_type.to_s
        when "permanent"
          true
        when "seasonal"
          seasonal_active?(rule, on: on)
        else
          date_window_active?(rule, on: on)
        end
      end

      def seasonal_active?(rule, on:)
        if season_fields?(rule)
          date = date_value(on)
          start_date = Date.new(date.year, rule.season_start_month, rule.season_start_day)
          end_date = Date.new(date.year, rule.season_end_month, rule.season_end_day)

          if start_date <= end_date
            date.between?(start_date, end_date)
          else
            date >= start_date || date <= end_date
          end
        else
          date_window_active?(rule, on: on)
        end
      rescue Date::Error
        false
      end

      def season_fields?(rule)
        [
          rule.season_start_month,
          rule.season_start_day,
          rule.season_end_month,
          rule.season_end_day
        ].all?
      end

      def date_window_active?(rule, on:)
        date = date_value(on)
        start_date = rule.effective_start
        end_date = rule.effective_end

        return false if start_date && date < start_date
        return false if end_date && date > end_date

        true
      end

      def date_value(value)
        return value if value.is_a?(Date)

        value.to_date
      end

      def sort_key(rule)
        [
          duration_rank(rule.duration_type),
          rule.title.to_s,
          rule.id.to_i
        ]
      end

      def duration_rank(duration_type)
        {
          "temporary" => 0,
          "incident" => 1,
          "seasonal" => 2,
          "permanent" => 3
        }.fetch(duration_type.to_s, 9)
      end
    end
  end
end
