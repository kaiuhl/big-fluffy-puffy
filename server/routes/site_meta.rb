require "yaml"

module SiteMetaRoutes
  SITEMAP_URL_LIMIT = 45_000
  SITEMAP_STATIC_PATHS = [
    {path: "/", priority: "1.0"},
    {path: "/fire-restrictions", priority: "0.9"},
    {path: "/trip-check", priority: "0.8"},
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
    fire_restriction_sitemap_paths.map do |path|
      {loc: canonical_url(path), changefreq: "daily", priority: "0.7"}
    end
  end

  def trip_check_sitemap_entries(page)
    trip_check_sitemap_paths(page: page).map do |path|
      {loc: canonical_url(path), changefreq: "weekly", priority: "0.7"}
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
    <<~XML
      <url>
        <loc>#{xml_escape(entry.fetch(:loc))}</loc>
        <changefreq>#{xml_escape(entry.fetch(:changefreq))}</changefreq>
        <priority>#{xml_escape(entry.fetch(:priority))}</priority>
      </url>
    XML
  end

  def fire_restriction_sitemap_paths
    fire_restriction_records.filter_map do |record|
      record[:land_unit_url] || record[:forest_url] || ("/fire-restrictions/#{record[:slug]}" if record[:slug])
    end
  end

  def trip_check_sitemap_paths(page:)
    offset = (page - 1) * SITEMAP_URL_LIMIT
    active_trip_check_slugs(limit: SITEMAP_URL_LIMIT, offset: offset).map { |slug| "/trip-check/#{slug}" }
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

    BFP::Places::Place.where(active: true).count
  rescue Sequel::DatabaseError, LoadError
    manual_trip_check_slugs.length
  end

  def active_trip_check_slugs(limit:, offset:)
    require "bfp/places"

    BFP::Places::Place
      .where(active: true)
      .order(:slug)
      .limit(limit, offset)
      .select_map(:slug)
  rescue Sequel::DatabaseError, LoadError
    manual_trip_check_slugs.slice(offset, limit) || []
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

  def canonical_url(path)
    normalized_path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
    "#{canonical_site_url}#{normalized_path}"
  end

  def canonical_site_url
    host = ENV.fetch("CANONICAL_HOST", "bigfluffypuffy.org").to_s.strip
    host = "bigfluffypuffy.org" if host.empty?
    url = host.start_with?("http://", "https://") ? host : "https://#{host.sub(%r{\A/+}, "")}"
    url.chomp("/")
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
