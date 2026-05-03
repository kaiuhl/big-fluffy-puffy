require "aws-sdk-bedrockruntime"

module BFP
  module LLM
    class BedrockParserClient < ParserClient
      TOOL_NAME = "record_fire_restriction_observation"
      PRIMARY_MODEL_ID = "global.anthropic.claude-haiku-4-5-20251001-v1:0"

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
        result.merge(
          "parser_provider" => "bedrock",
          "parser_model_id" => selected_model
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
    end
  end
end
