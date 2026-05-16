module BFP
  module LLM
    class ParserClient
      FIRE_STATUS_VALUES = %w[unknown none advisory partial stage_1 stage_2 full closure year_round].freeze
      LOCALIZED_STATUS_VALUES = %w[unknown advisory partial stage_1 stage_2 full closure year_round].freeze
      CAMPFIRE_POLICY_VALUES = %w[unknown allowed developed_sites_only prohibited propane_allowed stoves_only].freeze
      STOVE_POLICY_VALUES = %w[unknown allowed prohibited developed_sites_only allowed_with_shutoff_valve].freeze
      DURATION_TYPE_VALUES = %w[unknown permanent seasonal temporary incident].freeze
      AREA_TYPE_VALUES = %w[
        unknown
        ranger_district
        wilderness
        corridor
        campground
        trail
        trailhead
        watershed
        incident_area
        administrative_area
        named_area
        map_area
        other
      ].freeze
      GEOMETRY_SOURCE_TYPE_VALUES = %w[
        unknown
        none
        text_description
        source_map
        source_pdf_map
        source_arcgis_feature
        geojson
        linked_map
      ].freeze

      LOCALIZED_RULE_SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[
          title
          status
          campfire_policy
          charcoal_policy
          gas_stove_policy
          liquid_fuel_stove_policy
          alcohol_stove_policy
          solid_fuel_stove_policy
          wood_stove_policy
          stove_shutoff_valve_required
          duration_type
          effective_start
          effective_end
          season_start_month
          season_start_day
          season_end_month
          season_end_day
          incident_name
          incident_number
          incident_url
          affected_area
          area_type
          geometry_source_type
          summary
          evidence_quotes
          confidence
          needs_review_reasons
        ],
        properties: {
          title: {
            type: ["string", "null"],
            description: "Short source-supported title for the localized fire-use rule."
          },
          status: {
            type: "string",
            enum: LOCALIZED_STATUS_VALUES
          },
          campfire_policy: {
            type: "string",
            enum: CAMPFIRE_POLICY_VALUES
          },
          charcoal_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          gas_stove_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          liquid_fuel_stove_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          alcohol_stove_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          solid_fuel_stove_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          wood_stove_policy: {
            type: "string",
            enum: STOVE_POLICY_VALUES
          },
          stove_shutoff_valve_required: {type: ["boolean", "null"]},
          duration_type: {
            type: "string",
            enum: DURATION_TYPE_VALUES
          },
          effective_start: {type: ["string", "null"], description: "ISO 8601 date or null"},
          effective_end: {type: ["string", "null"], description: "ISO 8601 date or null"},
          season_start_month: {type: ["integer", "null"], minimum: 1, maximum: 12},
          season_start_day: {type: ["integer", "null"], minimum: 1, maximum: 31},
          season_end_month: {type: ["integer", "null"], minimum: 1, maximum: 12},
          season_end_day: {type: ["integer", "null"], minimum: 1, maximum: 31},
          incident_name: {type: ["string", "null"]},
          incident_number: {type: ["string", "null"]},
          incident_url: {type: ["string", "null"]},
          affected_area: {type: ["string", "null"]},
          area_type: {
            type: "string",
            enum: AREA_TYPE_VALUES
          },
          geometry_source_type: {
            type: "string",
            enum: GEOMETRY_SOURCE_TYPE_VALUES
          },
          summary: {type: ["string", "null"]},
          evidence_quotes: {
            type: "array",
            items: {type: "string"},
            maxItems: 6
          },
          confidence: {type: "number", minimum: 0, maximum: 1},
          needs_review_reasons: {
            type: "array",
            items: {type: "string"},
            maxItems: 8
          }
        }
      }.freeze

      SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[
          status
          campfire_policy
          fire_danger_rating
          ifpl_level
          effective_start
          effective_end
          order_number
          affected_area
          summary
          evidence_quotes
          confidence
          needs_review_reasons
        ],
        properties: {
          status: {
            type: "string",
            enum: FIRE_STATUS_VALUES
          },
          campfire_policy: {
            type: "string",
            enum: CAMPFIRE_POLICY_VALUES
          },
          fire_danger_rating: {type: ["string", "null"]},
          ifpl_level: {type: ["string", "null"]},
          effective_start: {type: ["string", "null"], description: "ISO 8601 date or null"},
          effective_end: {type: ["string", "null"], description: "ISO 8601 date or null"},
          order_number: {type: ["string", "null"]},
          affected_area: {type: ["string", "null"]},
          summary: {type: ["string", "null"]},
          evidence_quotes: {
            type: "array",
            items: {type: "string"},
            maxItems: 6
          },
          confidence: {type: "number", minimum: 0, maximum: 1},
          needs_review_reasons: {
            type: "array",
            items: {type: "string"},
            maxItems: 8
          },
          localized_rules: {
            type: "array",
            description: "Active localized camping/backpacking fire-use restrictions; return [] when none are supported by the source text.",
            items: LOCALIZED_RULE_SCHEMA,
            maxItems: 20
          }
        }
      }.freeze

      def self.build
        return FakeParserClient.new if ENV.fetch("LLM_PROVIDER", "bedrock") == "fake"
        return FakeParserClient.new if BFP.env == "test"

        BedrockParserClient.new
      end
    end
  end
end
