require "digest"
require "net/http"
require "uri"

module BFP
  module FireRestrictions
    class Fetcher
      USER_AGENT = "BigFluffyPuffy Fire Restriction Monitor/1.0 (https://bigfluffypuffy.org)"
      DEFAULT_TIMEOUT_SECONDS = 15
      DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024

      def initialize(timeout_seconds: DEFAULT_TIMEOUT_SECONDS, max_body_bytes: DEFAULT_MAX_BODY_BYTES)
        @timeout_seconds = timeout_seconds
        @max_body_bytes = max_body_bytes
      end

      def fetch_source(source)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        now = Time.now
        response = request(fetch_url(source), source)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

        save_success(source, response, now, duration_ms)
      rescue => error
        duration_ms ||= ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        save_failure(source, error, now || Time.now, duration_ms)
      end

      private

      def fetch_url(source)
        return ArcgisAdapter.query_url(source.url) if source.source_type == "arcgis_feature_layer"

        source.url
      end

      def request(url, source, redirect_limit = 5)
        raise "Too many redirects while fetching #{url}" if redirect_limit <= 0

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout_seconds
        http.read_timeout = @timeout_seconds

        request = Net::HTTP::Get.new(uri)
        apply_request_headers(request, source)

        response = http.request(request)
        case response
        when Net::HTTPNotModified
          response.instance_variable_set(:@bfp_final_url, uri.to_s)
          response
        when Net::HTTPRedirection
          location = response["location"].to_s
          raise "Redirect response did not include a Location header" if location.empty?

          request(URI.join(url, location).to_s, source, redirect_limit - 1)
        else
          body = response.body.to_s
          raise "Response exceeded #{@max_body_bytes} bytes" if body.bytesize > @max_body_bytes

          response.instance_variable_set(:@bfp_final_url, uri.to_s)
          response
        end
      end

      def apply_conditional_headers(request, source)
        latest = source.source_fetches_dataset.exclude(etag: nil).reverse(:fetched_at).first ||
          source.source_fetches_dataset.exclude(last_modified: nil).reverse(:fetched_at).first
        return unless latest

        request["If-None-Match"] = latest.etag if latest.etag
        request["If-Modified-Since"] = latest.last_modified if latest.last_modified
      end

      def apply_request_headers(request, source)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "text/html,application/pdf,application/json;q=0.9,*/*;q=0.5"
        apply_nps_api_key(request, source)
        apply_conditional_headers(request, source)
      end

      def apply_nps_api_key(request, source)
        return unless source.source_type == "nps_alerts_api"

        api_key = ENV["NPS_API_KEY"].to_s.strip
        raise "NPS_API_KEY is required to fetch NPS alerts API sources." if api_key.empty?

        request["X-Api-Key"] = api_key
      end

      def save_success(source, response, fetched_at, duration_ms)
        body = response.body.to_s
        content_hash = body.empty? ? nil : Digest::SHA256.hexdigest(body)
        document = document_for(response, content_hash, body)
        content_changed = content_hash && content_hash != latest_content_hash(source)

        fetch = SourceFetch.create(
          restriction_source_id: source.id,
          source_document_id: document&.id,
          fetched_at: fetched_at,
          http_status: response.code.to_i,
          final_url: response.instance_variable_get(:@bfp_final_url),
          etag: response["etag"],
          last_modified: response["last-modified"],
          content_type: response["content-type"],
          content_hash: content_hash,
          content_changed: !!content_changed,
          duration_ms: duration_ms,
          metadata_json: Jsonb.wrap(headers: safe_headers(response))
        )

        update_source_checked_at(source, fetched_at, content_changed)
        fetch
      end

      def save_failure(source, error, fetched_at, duration_ms)
        fetch = SourceFetch.create(
          restriction_source_id: source.id,
          fetched_at: fetched_at,
          content_changed: false,
          error_class: error.class.name,
          error_message: error.message,
          duration_ms: duration_ms,
          metadata_json: Jsonb.wrap({})
        )
        update_source_checked_at(source, fetched_at, false)
        fetch
      end

      def document_for(response, content_hash, body)
        return unless response.code.to_i.between?(200, 299)
        return unless content_hash

        SourceDocument.first(content_hash: content_hash) ||
          SourceDocument.create(
            content_hash: content_hash,
            content_type: response["content-type"],
            body: Sequel.blob(body),
            metadata_json: Jsonb.wrap({})
          )
      end

      def latest_content_hash(source)
        source.source_fetches_dataset.exclude(content_hash: nil).reverse(:fetched_at).first&.content_hash
      end

      def update_source_checked_at(source, checked_at, content_changed)
        source.last_checked_at = checked_at
        source.last_changed_at = checked_at if content_changed
        source.updated_at = checked_at
        source.save
      end

      def safe_headers(response)
        response.each_header.to_h.slice("etag", "last-modified", "content-type", "cache-control")
      end
    end
  end
end
