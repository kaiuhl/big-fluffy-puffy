module BFP
  module FireRestrictions
    class ReviewPresenter
      def queue(limit: 20, status: nil, land_unit: nil)
        dataset = RestrictionObservation.where(review_status: "needs_review")
        dataset = dataset.where(status: status.to_s) if present?(status)
        dataset = dataset.where(land_unit_id: land_unit_id(land_unit)) if present?(land_unit)

        dataset
          .reverse(:created_at)
          .limit(limit.to_i)
          .all
          .map { |observation| row(observation) }
      end

      def candidates(limit: nil, status: nil, land_unit: nil)
        units = LandUnit.where(active: true).order(:market_bucket, :name).all
        units = units.select { |unit| unit.slug == land_unit.to_s } if present?(land_unit)

        rows = units.filter_map do |unit|
          observations = candidate_observations(unit, status: status)
          next if observations.empty?

          row(observations.max_by { |observation| candidate_score(observation) }).merge(
            reviewed_observations: observations.length,
            best_candidate: true
          )
        end

        limit ? rows.first(limit.to_i) : rows
      end

      def forest(slug)
        land_unit = LandUnit.first(slug: slug.to_s)
        raise "Unknown land unit: #{slug}" unless land_unit

        RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: "needs_review")
          .all
          .sort_by { |observation| candidate_score(observation) }
          .reverse
          .map { |observation| row(observation).merge(score: candidate_score(observation)) }
      end

      def detail(observation_id)
        observation = RestrictionObservation[Integer(observation_id)]
        raise "Unknown restriction observation: #{observation_id}" unless observation

        fetch = observation.source_fetch
        document = fetch&.source_document

        row(observation).merge(
          review_status: observation.review_status,
          fire_danger_rating: observation.fire_danger_rating,
          ifpl_level: observation.ifpl_level,
          effective_start: observation.effective_start&.iso8601,
          effective_end: observation.effective_end&.iso8601,
          order_number: observation.order_number,
          affected_area: observation.affected_area,
          summary: observation.summary,
          evidence_quotes: json_array(observation.evidence_quotes),
          needs_review_reasons: json_array(observation.needs_review_reasons),
          validation_errors: json_array(observation.validation_errors),
          parser_provider: observation.parser_provider,
          parser_model_id: observation.parser_model_id,
          llm_usage: observation.raw_output && observation.raw_output["llm_usage"],
          estimated_cost_usd: observation.raw_output && observation.raw_output["llm_cost_estimate_usd"],
          fetch: fetch_details(fetch),
          document: document_details(document),
          commands: review_commands(observation)
        )
      end

      def format_queue(limit: 20, status: nil, land_unit: nil)
        rows = queue(limit: limit, status: status, land_unit: land_unit)
        return "No observations need review." if rows.empty?

        rows.map do |row|
          reasons = row[:needs_review_reasons].first(2).join("; ")
          [
            row[:id],
            row[:forest],
            row[:source],
            row[:status],
            row[:campfire_policy],
            "confidence=#{row[:confidence]}",
            "checked=#{row[:fetched_at] || "unknown"}",
            reasons
          ].compact.join(" | ")
        end.join("\n")
      end

      def format_candidates(limit: nil, status: nil, land_unit: nil)
        rows = candidates(limit: limit, status: status, land_unit: land_unit)
        return "No candidate observations need review." if rows.empty?

        rows.map do |row|
          reasons = row[:needs_review_reasons].first(2).join("; ")
          [
            row[:id],
            row[:forest],
            row[:source],
            row[:status],
            row[:campfire_policy],
            "confidence=#{row[:confidence]}",
            "candidates=#{row[:reviewed_observations]}",
            "checked=#{row[:fetched_at] || "unknown"}",
            reasons
          ].compact.join(" | ")
        end.join("\n")
      end

      def format_forest(slug)
        rows = forest(slug)
        return "No observations need review for #{slug}." if rows.empty?

        rows.map do |row|
          reasons = row[:needs_review_reasons].first(2).join("; ")
          [
            row[:id],
            row[:source],
            row[:status],
            row[:campfire_policy],
            "confidence=#{row[:confidence]}",
            "score=#{row[:score]}",
            "checked=#{row[:fetched_at] || "unknown"}",
            reasons
          ].compact.join(" | ")
        end.join("\n")
      end

      def format_detail(observation_id)
        data = detail(observation_id)
        lines = [
          "Observation #{data[:id]}",
          "Forest: #{data[:forest]}",
          "Source: #{data[:source]}",
          "Source URL: #{data[:source_url]}",
          "Status: #{data[:status]}",
          "Campfire policy: #{data[:campfire_policy]}",
          "Confidence: #{data[:confidence]}",
          "Review: #{data[:review_status]}",
          "Checked: #{data.dig(:fetch, :fetched_at) || "unknown"}",
          "Summary: #{data[:summary] || "(none)"}"
        ]

        lines << "Evidence:"
        lines.concat(format_list(data[:evidence_quotes]))
        lines << "Needs review:"
        lines.concat(format_list(data[:needs_review_reasons]))
        lines << "Validation errors:"
        lines.concat(format_list(data[:validation_errors]))
        lines << "Commands:"
        lines.concat(data[:commands].map { |command| "  #{command}" })
        lines.join("\n")
      end

      private

      def row(observation)
        {
          id: observation.id,
          forest: observation.land_unit.name,
          forest_slug: observation.land_unit.slug,
          source: observation.restriction_source.slug,
          source_name: observation.restriction_source.name,
          source_type: observation.restriction_source.source_type,
          source_url: observation.source_url || observation.restriction_source.url,
          status: observation.status,
          campfire_policy: observation.campfire_policy,
          confidence: observation.confidence,
          created_at: observation.created_at&.iso8601,
          fetched_at: observation.source_fetch&.fetched_at&.iso8601,
          needs_review_reasons: json_array(observation.needs_review_reasons)
        }
      end

      def candidate_observations(land_unit, status: nil)
        dataset = RestrictionObservation
          .where(land_unit_id: land_unit.id, review_status: "needs_review")
        dataset = dataset.where(status: status.to_s) if present?(status)
        dataset.all
      end

      def candidate_score(observation)
        source = observation.restriction_source
        [
          status_rank(observation.status),
          validation_rank(observation),
          source_rank(source.source_type),
          (observation.confidence.to_f * 100).round,
          observation.created_at || Time.at(0)
        ]
      end

      def status_rank(status)
        case status.to_s
        when "closure", "full", "stage_2", "stage_1", "partial", "year_round"
          600
        when "none"
          500
        when "advisory"
          350
        else
          0
        end
      end

      def validation_rank(observation)
        json_array(observation.validation_errors).empty? ? 50 : 0
      end

      def source_rank(source_type)
        Resolver::SOURCE_PRECEDENCE.fetch(source_type.to_s, 0)
      end

      def fetch_details(fetch)
        return unless fetch

        {
          id: fetch.id,
          fetched_at: fetch.fetched_at&.iso8601,
          http_status: fetch.http_status,
          final_url: fetch.final_url,
          error_class: fetch.error_class,
          error_message: fetch.error_message,
          content_changed: fetch.content_changed
        }
      end

      def document_details(document)
        return unless document

        {
          id: document.id,
          title: document.title,
          canonical_url: document.canonical_url,
          modified_at: document.modified_at&.iso8601,
          extraction_status: document.extraction_status,
          extraction_error: document.extraction_error
        }
      end

      def review_commands(observation)
        [
          "bin/prod-console -e 'review_observation(#{observation.id})'",
          "bin/prod-console -e 'accept_observation(#{observation.id})'",
          "bin/prod-console -e 'reject_observation(#{observation.id}, \"reason\")'"
        ]
      end

      def format_list(values)
        values = json_array(values)
        return ["  (none)"] if values.empty?

        values.map { |value| "  - #{value}" }
      end

      def json_array(value)
        return [] if value.nil?
        return value if value.is_a?(Array)
        return value.to_a if value.respond_to?(:to_a)

        [value]
      end

      def land_unit_id(slug)
        land_unit = LandUnit.first(slug: slug.to_s)
        raise "Unknown land unit: #{slug}" unless land_unit

        land_unit.id
      end

      def present?(value)
        !value.nil? && value.to_s != ""
      end
    end
  end
end
