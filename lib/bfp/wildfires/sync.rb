require "net/http"
require "uri"
require_relative "feed"

module BFP
  module Wildfires
    # Fetches both NIFC/WFIGS feeds, upserts the PNW incident set, deactivates
    # incidents that dropped out of the feed, and records an audit row on both
    # success and failure. Never raises out; callers get a counts hash.
    class Sync
      USER_AGENT = BFP::FireRestrictions::Fetcher::USER_AGENT
      TIMEOUT_SECONDS = 15
      MAX_BODY_BYTES = 8 * 1024 * 1024
      REDIRECT_LIMIT = 5

      Response = Struct.new(:code, :body)

      def initialize(timeout_seconds: TIMEOUT_SECONDS, max_body_bytes: MAX_BODY_BYTES)
        @timeout_seconds = timeout_seconds
        @max_body_bytes = max_body_bytes
      end

      def run
        started_at = Time.now
        monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        points = get(Feed.points_query_url)
        perimeters = get(Feed.perimeters_query_url)
        # InciWeb only carries the larger, staffed incidents and is a best-effort
        # enrichment; a failed or unparseable RSS reply must not fail the sync.
        inciweb = fetch_inciweb_entries
        incidents = Feed.parse(points.body, perimeters.body, inciweb_entries: inciweb[:entries])
        # An empty points response would deactivate every incident and let the
        # site claim "no fires" off one bad upstream reply; fail the run and
        # keep the previous set instead.
        raise Feed::FeedError, "points feed returned zero incidents for the PNW envelope" if incidents.empty?

        counts = persist(incidents)
        perimeter_count = incidents.count { |incident| incident[:perimeter_geometry_json] }
        information_url_count = incidents.count { |incident| incident[:information_url] }

        record_sync(
          started_at: started_at,
          success: true,
          points_status: points.code,
          perimeters_status: perimeters.code,
          incident_count: counts[:incidents],
          perimeter_count: perimeter_count,
          duration_ms: elapsed_ms(monotonic),
          metadata: sync_metadata(counts[:deactivated], information_url_count, inciweb[:error])
        )

        {incidents: counts[:incidents], perimeters: perimeter_count, deactivated: counts[:deactivated], success: true}
      rescue => error
        record_sync(
          started_at: started_at || Time.now,
          success: false,
          points_status: points&.code,
          perimeters_status: perimeters&.code,
          duration_ms: elapsed_ms(monotonic),
          error: error
        )
        {incidents: 0, perimeters: 0, deactivated: 0, success: false}
      end

      private

      # Fetches and parses the InciWeb RSS without letting a failure escape:
      # returns the parsed entries plus the error (if any) so the caller can
      # proceed with no links and record the error class in sync metadata.
      def fetch_inciweb_entries
        response = get(Feed::INCIWEB_RSS_URL)
        {entries: Feed.parse_inciweb(response.body), error: nil}
      rescue => error
        {entries: [], error: error}
      end

      def sync_metadata(deactivated, information_url_count, inciweb_error)
        metadata = {deactivated: deactivated, information_urls: information_url_count}
        metadata[:inciweb_error] = inciweb_error.class.name if inciweb_error
        metadata
      end

      def persist(incidents)
        now = Time.now
        seen = []

        WildfireIncident.db.transaction do
          existing_perimeters = WildfireIncident.exclude(perimeter_geometry_json: nil).select_map(:irwin_id).to_set
          existing_information_urls = WildfireIncident.exclude(information_url: nil).select_map(:irwin_id).to_set

          incidents.each do |attrs|
            row = row_for(attrs, now)
            seen << row[:irwin_id]
            update = row.except(:first_seen_at, :created_at)
            # The perimeters feed intermittently returns empty while the points
            # feed stays populated; keep the last known perimeter (and its
            # AABB) rather than degrading an active fire back to a point.
            if attrs[:perimeter_geometry_json].nil? && existing_perimeters.include?(row[:irwin_id])
              update = update.except(:perimeter_geometry_json, :min_lon, :min_lat, :max_lon, :max_lat)
            end
            # InciWeb only lists staffed incidents and drops them once staffing
            # ends; keep the last known information link rather than clearing it
            # on a run where the RSS had no (or no matching) entry.
            if attrs[:information_url].nil? && existing_information_urls.include?(row[:irwin_id])
              update = update.except(:information_url)
            end
            WildfireIncident.dataset.insert_conflict(target: :irwin_id, update: update).insert(row)
          end

          deactivated = deactivate_missing(seen, now)
          {incidents: incidents.length, deactivated: deactivated}
        end
      end

      def deactivate_missing(seen, now)
        scope = WildfireIncident.where(active: true)
        scope = scope.exclude(irwin_id: seen) unless seen.empty?
        scope.update(active: false, updated_at: now)
      end

      def row_for(attrs, now)
        attrs.merge(
          perimeter_geometry_json: BFP::FireRestrictions::Jsonb.wrap(attrs[:perimeter_geometry_json]),
          attributes_json: BFP::FireRestrictions::Jsonb.wrap(attrs[:attributes_json]),
          active: true,
          first_seen_at: now,
          last_seen_at: now,
          created_at: now,
          updated_at: now
        )
      end

      def record_sync(started_at:, success:, duration_ms:, points_status: nil, perimeters_status: nil, incident_count: nil, perimeter_count: nil, metadata: {}, error: nil)
        WildfireSync.create(
          started_at: started_at,
          finished_at: Time.now,
          success: success,
          points_http_status: points_status&.to_i,
          perimeters_http_status: perimeters_status&.to_i,
          incident_count: incident_count,
          perimeter_count: perimeter_count,
          error_class: error&.class&.name,
          error_message: error&.message,
          duration_ms: duration_ms,
          metadata_json: BFP::FireRestrictions::Jsonb.wrap(metadata)
        )
      rescue Sequel::DatabaseError
        nil
      end

      def elapsed_ms(monotonic)
        return unless monotonic

        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic) * 1000).round
      end

      def get(url, redirect_limit = REDIRECT_LIMIT)
        raise "Too many redirects while fetching #{url}" if redirect_limit <= 0

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout_seconds
        http.read_timeout = @timeout_seconds

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/geo+json,application/json;q=0.9,*/*;q=0.5"

        response = http.request(request)
        case response
        when Net::HTTPRedirection
          location = response["location"].to_s
          raise "Redirect response did not include a Location header" if location.empty?

          get(URI.join(url, location).to_s, redirect_limit - 1)
        else
          body = response.body.to_s
          raise "Response exceeded #{@max_body_bytes} bytes" if body.bytesize > @max_body_bytes
          raise "Wildfire feed request failed: #{uri} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          Response.new(response.code, body)
        end
      end
    end
  end
end
