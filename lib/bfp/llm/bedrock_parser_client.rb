require "aws-sdk-bedrockruntime"

module BFP
  module LLM
    class BedrockParserClient < ParserClient
      TOOL_NAME = "record_fire_restriction_observation"
      PRIMARY_MODEL_ID = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
      PRICING_BY_MODEL_PATTERN = [
        [
          /haiku-4-5/,
          {
            input_per_million: 1.0,
            output_per_million: 5.0
          }
        ],
        [
          /sonnet-4-5/,
          {
            input_per_million: 3.0,
            output_per_million: 15.0
          }
        ]
      ].freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        You parse official wildfire and public-use restriction source text into structured observations for camping/backpacking fire-use.

        Rules:
        - Use only the supplied text. Do not infer from outside knowledge.
        - If the text does not explicitly support a field, return null or "unknown".
        - Evidence quotes must be exact short spans from the supplied text.
        - Scope is camping/backpacking fire-use: campfires, charcoal or wood fires, and cooking or heating stoves used for camping/backpacking.
        - Include charcoal restrictions and stove restrictions for gas, liquid-fuel, alcohol, solid fuel/tablet, and wood/biomass stoves, including shutoff valve requirements.
        - Use campfire_policy "fire_pan_required" when open fires are allowed only in a fire pan or equivalent contained device.
        - Exclude chainsaws, welding, industrial IFPL, generators, off-road travel, and other industrial or motorized-use rules unless the text directly ties them to camping/backpacking fire-use.
        - Restrictive statuses require prohibition, restriction, order, closure, or Stage 1/Stage 2 evidence.
        - A "none" status requires explicit "no restrictions", "lifted", "rescinded", or equivalent evidence.
        - Low fire danger, no featured alerts, or absence of a restriction is not enough by itself for "none".
        - A generated Forest Alert Summary line saying no active forest fire restriction alerts were listed can support "none" for seasonal USFS forest-wide public-use restrictions.
        - A generated NPS Alert Summary saying no fire-related NPS alerts were returned is not enough by itself for "none"; use it only as context alongside explicit park fire-ban or restriction text.
        - NPS alerts can support active restrictions only when the alert title or description explicitly states a current fire restriction, fire ban, campfire ban, or fire closure.
        - Ignore Alerts Key labels, Region Alerts, fireworks/explosives boilerplate, fire danger definitions, and unrelated road/camping/occupancy closures when deciding seasonal fire restriction status.
        - Keep the top-level fields focused on the current forest-wide or land-unit-wide camping/backpacking fire-use posture.
        - If an active camping/backpacking fire-use restriction is geographically limited, wilderness-only, corridor-only, incident-area-only, campground-only, or trail-specific, mark the top-level status partial and include the localized rule in localized_rules.
        - Only include localized_rules entries for active localized camping/backpacking fire-use restrictions. Do not include inactive, rescinded, lifted, expired, future-only, purely industrial, or non-fire-use entries.
        - Use duration_type "permanent" for standing/year-round rules, "seasonal" for recurring month/day seasons, "temporary" for date-limited non-incident rules, and "incident" for restrictions tied to an active wildfire or incident area.
        - Current "PUR: Seasonal Restrictions" or Phase A public-use restrictions should be advisory unless the current phase explicitly prohibits campfires. Treat IFPL as industrial-only unless the source ties it to camping/backpacking fire-use or a current public-use restrictions table.
        - InciWeb, NIFC, and active incident context cannot determine campfire policy.
        - Prefer needs_review_reasons over guessing.
      PROMPT

      def initialize(client: nil)
        @client = client || Aws::BedrockRuntime::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"))
      end

      def parse(text:, source:, land_unit:, model_id: nil)
        selected_model = model_id || ENV.fetch("BEDROCK_PRIMARY_MODEL_ID", PRIMARY_MODEL_ID)
        response = @client.invoke_model(
          model_id: selected_model,
          content_type: "application/json",
          accept: "application/json",
          body: JSON.generate(request_body(text, source, land_unit))
        )

        parsed = JSON.parse(response.body.read)
        result = tool_result(parsed) || text_result(parsed)
        usage = usage_from(parsed)
        result.merge(
          "parser_provider" => "bedrock",
          "parser_model_id" => selected_model,
          "llm_usage" => usage,
          "llm_cost_estimate_usd" => estimate_cost(selected_model, usage)
        )
      end

      private

      def request_body(text, source, land_unit)
        {
          anthropic_version: "bedrock-2023-05-31",
          max_tokens: 1400,
          temperature: 0,
          system: SYSTEM_PROMPT,
          tools: [
            {
              name: TOOL_NAME,
              description: "Record a structured public-use fire restriction observation.",
              input_schema: ParserClient::SCHEMA
            }
          ],
          tool_choice: {type: "tool", name: TOOL_NAME},
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: prompt_text(text, source, land_unit)
                }
              ]
            }
          ]
        }
      end

      def prompt_text(text, source, land_unit)
        <<~PROMPT
          Land unit: #{land_unit.name}
          Source type: #{source.source_type}
          Source URL: #{source.url}

          Source text:
          #{text.to_s[0, 45_000]}
        PROMPT
      end

      def tool_result(parsed)
        parsed.fetch("content", []).each do |content|
          next unless content["type"] == "tool_use"
          next unless content["name"] == TOOL_NAME

          return content["input"]
        end

        nil
      end

      def text_result(parsed)
        text = parsed.fetch("content", []).filter_map { |content| content["text"] }.join("\n")
        JSON.parse(text[/\{.*\}/m] || "{}")
      end

      def usage_from(parsed)
        usage = parsed.fetch("usage", {})
        {
          "input_tokens" => usage.fetch("input_tokens", 0).to_i,
          "output_tokens" => usage.fetch("output_tokens", 0).to_i,
          "cache_creation_input_tokens" => usage.fetch("cache_creation_input_tokens", 0).to_i,
          "cache_read_input_tokens" => usage.fetch("cache_read_input_tokens", 0).to_i
        }
      end

      def estimate_cost(model_id, usage)
        pricing = pricing_for(model_id)
        return unless pricing

        input_tokens = usage.fetch("input_tokens", 0) + usage.fetch("cache_creation_input_tokens", 0)
        output_tokens = usage.fetch("output_tokens", 0)
        cost = (input_tokens * pricing.fetch(:input_per_million) / 1_000_000.0) +
          (output_tokens * pricing.fetch(:output_per_million) / 1_000_000.0)
        cost.round(8)
      end

      def pricing_for(model_id)
        PRICING_BY_MODEL_PATTERN.each do |pattern, pricing|
          return pricing if model_id.to_s.match?(pattern)
        end

        nil
      end
    end
  end
end
