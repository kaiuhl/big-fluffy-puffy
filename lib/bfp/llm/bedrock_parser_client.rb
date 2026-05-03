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
        You parse official wildfire and public-use restriction source text into structured observations.

        Rules:
        - Use only the supplied text. Do not infer from outside knowledge.
        - If the text does not explicitly support a field, return null or "unknown".
        - Evidence quotes must be exact short spans from the supplied text.
        - Restrictive statuses require prohibition, restriction, order, closure, or Stage 1/Stage 2 evidence.
        - A "none" status requires explicit "no restrictions", "lifted", "rescinded", or equivalent evidence.
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
