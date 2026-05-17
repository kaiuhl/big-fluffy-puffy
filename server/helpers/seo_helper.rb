require "json"

module SeoHelper
  SITE_NAME = "Big Fluffy Puffy"

  def canonical_site_url
    host = ENV.fetch("CANONICAL_HOST", "bigfluffypuffy.org").to_s.strip
    host = "bigfluffypuffy.org" if host.empty?
    url = host.start_with?("http://", "https://") ? host : "https://#{host.sub(%r{\A/+}, "")}"
    url.chomp("/")
  end

  def canonical_url(path)
    normalized_path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
    "#{canonical_site_url}#{normalized_path}"
  end

  def google_analytics_measurement_id
    id = ENV["GOOGLE_ANALYTICS_MEASUREMENT_ID"].to_s.strip
    id unless id.empty?
  end

  def json_ld(payload)
    JSON.generate(payload).gsub("</", '<\/')
  end

  def seo_graph(*nodes)
    {
      "@context" => "https://schema.org",
      "@graph" => [organization_schema, website_schema, *nodes].compact
    }
  end

  def organization_schema
    {
      "@type" => "Organization",
      "@id" => canonical_url("/#organization"),
      "name" => SITE_NAME,
      "url" => canonical_url("/"),
      "description" => "Big Fluffy Puffy is a nonprofit building fireless outdoor culture in the Pacific Northwest."
    }
  end

  def website_schema
    {
      "@type" => "WebSite",
      "@id" => canonical_url("/#website"),
      "name" => SITE_NAME,
      "url" => canonical_url("/"),
      "publisher" => {"@id" => canonical_url("/#organization")},
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => "#{canonical_url("/trip-check")}?q={search_term_string}",
        "query-input" => "required name=search_term_string"
      }
    }
  end

  def webpage_schema(path:, title:, description:, breadcrumbs: nil)
    schema = {
      "@type" => "WebPage",
      "@id" => "#{canonical_url(path)}#webpage",
      "url" => canonical_url(path),
      "name" => title,
      "description" => description,
      "isPartOf" => {"@id" => canonical_url("/#website")},
      "publisher" => {"@id" => canonical_url("/#organization")}
    }
    schema["breadcrumb"] = {"@id" => "#{canonical_url(path)}#breadcrumb"} if breadcrumbs
    schema
  end

  def breadcrumb_schema(path:, items:)
    {
      "@type" => "BreadcrumbList",
      "@id" => "#{canonical_url(path)}#breadcrumb",
      "itemListElement" => items.each_with_index.map do |item, index|
        {
          "@type" => "ListItem",
          "position" => index + 1,
          "name" => item.fetch(:name),
          "item" => canonical_url(item.fetch(:path))
        }
      end
    }
  end

  def trip_check_seo_title(check)
    "#{check.dig(:place, :name)} Fire Restrictions & Campfire Trip Check | #{SITE_NAME}"
  end

  def trip_check_seo_description(check)
    place = check.fetch(:place)
    forest = check[:primary_forest]
    location = forest ? " in #{forest.fetch(:name)}" : ""
    answer = campfire_answer_statement(check.fetch(:campfire_policy), allowed_text: "No BFP campfire restriction matched.")

    "Source-linked campfire and fire-use trip check for #{place.fetch(:name)}#{location}. #{answer}"
  end

  def trip_check_meta_robots(check)
    indexable_trip_check?(check) ? nil : "noindex,follow"
  end

  def indexable_trip_check?(check)
    check[:primary_forest] ||
      check.fetch(:localized_restrictions, []).any? ||
      check.fetch(:datasets, []).any? { |dataset| dataset[:slug].to_s == "bfp-manual" }
  end

  def forest_restrictions_description(forest)
    "Source-linked campfire restrictions, localized fire-use rules, and overnight low context for #{forest.fetch(:name)}."
  end
end
