require "rack/utils"

module BFP
  module FireRestrictions
    class FireUseSparkline
      POINT_WIDTH = 46
      POINT_GAP = 7

      ITEMS = [
        {
          key: :campfire_policy,
          chart_label: "Campfires",
          aria_label: "campfires",
          summary_label: "campfires",
          kind: :campfire
        },
        {
          key: :gas_stove_policy,
          chart_label: "Gas stoves",
          aria_label: "gas stoves",
          summary_label: "gas stoves",
          kind: :stove
        },
        {
          key: :alcohol_stove_policy,
          chart_label: "Alcohol stoves",
          aria_label: "alcohol stoves",
          summary_label: "alcohol stoves",
          kind: :stove
        },
        {
          key: :charcoal_policy,
          chart_label: "Charcoal",
          aria_label: "charcoal",
          summary_label: "charcoal",
          kind: :stove
        },
        {
          key: :solid_fuel_stove_policy,
          chart_label: "Solid fuel stoves",
          aria_label: "solid fuel stoves",
          summary_label: "solid fuel stoves",
          kind: :stove
        },
        {
          key: :wood_stove_policy,
          chart_label: "Wood stoves",
          aria_label: "wood stoves",
          summary_label: "wood stoves",
          kind: :stove
        }
      ].freeze

      def self.render(rule)
        new(rule).render
      end

      def self.summary(rule)
        new(rule).summary
      end

      def initialize(rule)
        @rule = rule || {}
      end

      def render
        items = visible_items
        return "" if items.empty?

        <<~HTML
          <span
            class="fire-use-sparkline"
            style="--fire-use-count: #{items.length}; --fire-use-width: #{chart_width(items.length)}px;"
            role="img"
            aria-label="#{h(aria_label)}">
            #{items.map { |item| point_markup(item) }.join}
          </span>
        HTML
      end

      def summary
        campfire_item = ITEMS.first
        campfire_clause = "#{capitalize_sentence(campfire_item.fetch(:summary_label))} #{policy_phrase(campfire_item, policy_for(campfire_item))}"
        stove_clauses = grouped_stove_clauses

        ([campfire_clause] + stove_clauses).join(". ") + "."
      end

      private

      def visible_items
        ITEMS.reject do |item|
          policy_state(policy_for(item)) == "unknown"
        end
      end

      def point_markup(item)
        state = policy_state(policy_for(item))

        <<~HTML
          <span class="fire-use-point fire-use-point-#{h(state)}">
            <svg class="fire-use-symbol" viewBox="-12 -12 24 24" aria-hidden="true" focusable="false">
              <circle class="fire-use-ring" cx="0" cy="0" r="9"></circle>
              #{state_mark(state)}
            </svg>
            <span class="fire-use-label">#{h(item.fetch(:chart_label))}</span>
          </span>
        HTML
      end

      def state_mark(state)
        case state
        when "allowed"
          %(<path class="fire-use-mark" d="M -5 0.2 L -1.6 4 L 5.6 -4.8"></path>)
        when "limited"
          %(<text class="fire-use-mark-text" x="0" y="0.6">!</text>)
        when "prohibited"
          %(<path class="fire-use-mark" d="M -5.3 5.3 L 5.3 -5.3"></path>)
        end
      end

      def chart_width(item_count)
        (item_count * POINT_WIDTH) + ([item_count - 1, 0].max * POINT_GAP)
      end

      def grouped_stove_clauses
        ITEMS.drop(1).each_with_object([]) do |item, groups|
          phrase = policy_phrase(item, policy_for(item))
          group = groups.find { |candidate| candidate.fetch(:phrase) == phrase }

          if group
            group.fetch(:labels) << item.fetch(:summary_label)
          else
            groups << {phrase: phrase, labels: [item.fetch(:summary_label)]}
          end
        end.map do |group|
          capitalize_sentence("#{join_labels(group.fetch(:labels))} #{group.fetch(:phrase)}")
        end
      end

      def policy_for(item)
        @rule[item.fetch(:key)] || @rule[item.fetch(:key).to_s]
      end

      def policy_state(policy)
        case normalized_policy(policy)
        when "allowed", "allowed_with_shutoff_valve"
          "allowed"
        when "developed_sites_only", "fire_pan_required"
          "limited"
        when "prohibited"
          "prohibited"
        else
          "unknown"
        end
      end

      def policy_phrase(item, policy)
        policy = normalized_policy(policy)

        case policy
        when "allowed"
          shutoff_required_for?(item, policy) ? "allowed with shutoff valve" : "allowed"
        when "allowed_with_shutoff_valve"
          "allowed with shutoff valve"
        when "developed_sites_only"
          shutoff_required_for?(item, policy) ? "limited to developed sites with shutoff valve" : "limited to developed sites"
        when "fire_pan_required"
          "allowed only with a fire pan"
        when "prohibited"
          "prohibited"
        else
          "unknown"
        end
      end

      def normalized_policy(policy)
        policy.to_s.empty? ? "unknown" : policy.to_s
      end

      def shutoff_required_for?(item, policy)
        item.fetch(:kind) == :stove &&
          (@rule[:stove_shutoff_valve_required] == true || @rule["stove_shutoff_valve_required"] == true) &&
          !["prohibited", "unknown"].include?(normalized_policy(policy))
      end

      def aria_label
        descriptions = visible_items.map do |item|
          "#{item.fetch(:aria_label)} #{policy_phrase(item, policy_for(item))}"
        end

        "Fire use: #{descriptions.join(", ")}"
      end

      def join_labels(labels)
        return labels.first.to_s if labels.length == 1
        return labels.join(" and ") if labels.length == 2

        "#{labels[0...-1].join(", ")}, and #{labels.last}"
      end

      def capitalize_sentence(value)
        value.to_s.sub(/\A[a-z]/) { |character| character.upcase }
      end

      def h(value)
        Rack::Utils.escape_html(value.to_s)
      end
    end
  end
end
