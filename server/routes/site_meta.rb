require "yaml"

module SiteMetaRoutes
  SITEMAP_URL_LIMIT = 45_000
  INDEXABLE_TRIP_CHECK_TYPES = %w[
    campground
    destination
    lake
    localized_restriction_area
    trail
    trailhead
    wilderness
  ].freeze
  SITEMAP_STATIC_PATHS = [
    {path: "/", priority: "1.0"},
    {path: "/fire-restrictions", priority: "0.9"},
    {path: "/why-fireless", priority: "0.5"},
    {path: "/about", priority: "0.5"},
    {path: "/contact", priority: "0.4"}
  ].freeze

  def route_site_meta(r)
    r.get "sitemap.xml" do
      xml_response(sitemap_index_xml)
    end

    r.on "sitemaps" do
      r.get "static.xml" do
        xml_response(sitemap_urlset_xml(static_sitemap_entries))
      end

      r.get String do |filename|
        page = trip_check_sitemap_page(filename)
        next xml_response("", status: 404) unless page

        xml_response(sitemap_urlset_xml(trip_check_sitemap_entries(page)))
      end
    end
  end

  private

  def sitemap_index_xml
    body = sitemap_index_entries.map { |entry| sitemap_index_entry_xml(entry) }.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{body}</sitemapindex>
    XML
  end

  def sitemap_urlset_xml(entries)
    body = entries.map { |entry| sitemap_url_xml(entry) }.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{body}</urlset>
    XML
  end

  def sitemap_index_entries
    entries = [{loc: canonical_url("/sitemaps/static.xml")}]
    entries.concat(
      (1..trip_check_sitemap_page_count).map do |page|
        {loc: canonical_url("/sitemaps/trip-check-#{page}.xml")}
      end
    )
    entries
  end

  def static_sitemap_entries
    entries = SITEMAP_STATIC_PATHS.map do |entry|
      {
        loc: canonical_url(entry.fetch(:path)),
        changefreq: "weekly",
        priority: entry.fetch(:priority)
      }
    end

    entries.concat(fire_restriction_sitemap_entries)

    entries.uniq { |entry| entry.fetch(:loc) }
  end

  def fire_restriction_sitemap_entries
    fire_restriction_records.filter_map do |record|
      path = fire_restriction_sitemap_path(record)
      next unless path

      {
        loc: canonical_url(path),
        lastmod: sitemap_lastmod(checked_at_for(record, preferred_source(record))),
        changefreq: "daily",
        priority: "0.7"
      }.compact
    end
  end

  def trip_check_sitemap_entries(page)
    trip_check_sitemap_rows(page: page).map do |row|
      {
        loc: canonical_url("/trip-check/#{row.fetch(:slug)}"),
        lastmod: sitemap_lastmod(row[:updated_at]),
        changefreq: "weekly",
        priority: "0.7"
      }.compact
    end
  end

  def sitemap_index_entry_xml(entry)
    <<~XML
      <sitemap>
        <loc>#{xml_escape(entry.fetch(:loc))}</loc>
      </sitemap>
    XML
  end

  def sitemap_url_xml(entry)
    [
      "  <url>",
      "    <loc>#{xml_escape(entry.fetch(:loc))}</loc>",
      ("    <lastmod>#{xml_escape(entry[:lastmod])}</lastmod>" if entry[:lastmod]),
      "    <changefreq>#{xml_escape(entry.fetch(:changefreq))}</changefreq>",
      "    <priority>#{xml_escape(entry.fetch(:priority))}</priority>",
      "  </url>"
    ].compact.join("\n") + "\n"
  end

  def fire_restriction_sitemap_path(record)
    record[:land_unit_url] || record[:forest_url] || ("/fire-restrictions/#{record[:slug]}" if record[:slug])
  end

  def trip_check_sitemap_rows(page:)
    offset = (page - 1) * SITEMAP_URL_LIMIT
    active_trip_check_rows(limit: SITEMAP_URL_LIMIT, offset: offset)
  end

  def trip_check_sitemap_paths(page:)
    trip_check_sitemap_rows(page: page).map { |row| "/trip-check/#{row.fetch(:slug)}" }
  end

  def trip_check_sitemap_page(filename)
    match = filename.match(/\Atrip-check-(\d+)\.xml\z/)
    return unless match

    page = Integer(match[1])
    page if page.between?(1, trip_check_sitemap_page_count)
  end

  def trip_check_sitemap_page_count
    count = active_trip_check_slug_count
    return 0 if count.zero?

    (count.to_f / SITEMAP_URL_LIMIT).ceil
  end

  def active_trip_check_slug_count
    require "bfp/places"

    indexable_trip_check_places.count
  rescue Sequel::DatabaseError, LoadError
    manual_trip_check_slugs.length
  end

  def active_trip_check_rows(limit:, offset:)
    require "bfp/places"

    indexable_trip_check_places
      .order(:slug)
      .limit(limit, offset)
      .select(:slug, :updated_at)
      .all
      .map { |place| {slug: place.slug, updated_at: place.updated_at} }
  rescue Sequel::DatabaseError, LoadError
    (manual_trip_check_slugs.slice(offset, limit) || []).map { |slug| {slug: slug} }
  end

  def indexable_trip_check_places
    require "bfp/places"

    manual_dataset_ids = BFP::Places::PlaceDataset.where(slug: "bfp-manual").select(:id)
    localized_place_ids = BFP::Places::PlaceLocalizedRuleMatch.select(:place_id)
    land_unit_place_ids = BFP::Places::PlaceLandUnitMatch.select(:place_id)

    BFP::Places::Place
      .where(active: true)
      .where(
        Sequel.|(
          {source_dataset_id: manual_dataset_ids},
          {id: localized_place_ids},
          Sequel.&({place_type: INDEXABLE_TRIP_CHECK_TYPES}, {id: land_unit_place_ids})
        )
      )
      .distinct
  end

  def manual_trip_check_slugs
    config = YAML.load_file(File.join(BFP.root, "config/place_manual.yml"))
    Array(config["places"]).filter_map do |place|
      slug = place["slug"].to_s.strip
      slug unless slug.empty?
    end
  rescue Errno::ENOENT, Psych::Exception
    []
  end

  def sitemap_lastmod(value)
    return unless value

    if value.respond_to?(:iso8601)
      value.iso8601.split("T").first
    else
      Time.parse(value.to_s).utc.iso8601.split("T").first
    end
  rescue ArgumentError
    nil
  end

  def xml_escape(value)
    Rack::Utils.escape_html(value.to_s)
  end

  def xml_response(body, status: 200)
    response.status = status
    response["Content-Type"] = "application/xml"
    body
  end
end
