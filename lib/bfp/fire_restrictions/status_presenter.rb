module BFP
  module FireRestrictions
    class StatusPresenter
      def forests
        LandUnit
          .where(active: true)
          .order(:market_bucket, :name)
          .all
          .map { |land_unit| serialize_land_unit(land_unit) }
      rescue Sequel::DatabaseError
        []
      end

      private

      def serialize_land_unit(land_unit)
        status = land_unit.restriction_status

        {
          slug: land_unit.slug,
          name: land_unit.name,
          unit_type: land_unit.unit_type,
          market_bucket: land_unit.market_bucket,
          region_code: land_unit.region_code,
          status: status&.status || "unknown",
          campfire_policy: status&.campfire_policy || "unknown",
          fire_danger_rating: status&.fire_danger_rating,
          ifpl_level: status&.ifpl_level,
          confidence: status&.confidence || 0.0,
          review_status: status&.review_status || "needs_review",
          effective_start: status&.effective_start&.iso8601,
          effective_end: status&.effective_end&.iso8601,
          order_number: status&.order_number,
          affected_area: status&.affected_area,
          summary: status&.summary,
          evidence_quotes: status&.evidence_quotes || [],
          last_checked_at: status&.last_checked_at&.iso8601,
          source_url: status&.source_url,
          source_title: status&.source_title,
          sources: land_unit.metadata_sources.map { |source| serialize_source(source) }
        }
      end

      def serialize_source(source)
        {
          slug: source.slug,
          name: source.name,
          source_type: source.source_type,
          authority: source.authority,
          url: source.url,
          last_checked_at: source.last_checked_at&.iso8601
        }
      end
    end
  end
end
