require "nokogiri"
require "time"

module BFP
  module FireRestrictions
    module Extractors
      class HtmlExtractor
        KEYWORD_PATTERN = /fire|restriction|campfire|camp fire|public use|IFPL|industrial fire|forest order|closure|prohibit|ban|danger/i

        def extract(body, final_url: nil)
          html = body.to_s
          document = Nokogiri::HTML(html)
          title = text_at(document, "title") || text_at(document, "h1")
          canonical_url = canonical_url(document) || final_url
          modified_at = modified_at(document)

          document.css("script, style, noscript, svg").remove

          headings = document.css("h1, h2, h3").map { |node| clean(node.text) }.reject(&:empty?)
          links = keyword_links(document, canonical_url)
          excerpts = keyword_excerpts(document)
          body_text = clean((document.at_css("main") || document.at_css("body") || document).text)

          extracted_text = [
            ("Title: #{title}" if title),
            ("Canonical URL: #{canonical_url}" if canonical_url),
            ("Modified: #{modified_at.iso8601}" if modified_at),
            headings_section(headings),
            links_section(links),
            excerpts_section(excerpts),
            "Body:",
            body_text
          ].compact.join("\n")

          {
            title: title,
            canonical_url: canonical_url,
            modified_at: modified_at,
            extracted_text: extracted_text,
            extraction_status: "ok",
            metadata_json: {
              headings: headings.first(60),
              keyword_links: links.first(80),
              keyword_excerpt_count: excerpts.length
            }
          }
        end

        private

        def text_at(document, selector)
          value = document.at_css(selector)&.text
          value && clean(value)
        end

        def canonical_url(document)
          document.at_css("link[rel='canonical'], link[rel='Canonical']")&.[]("href")
        end

        def modified_at(document)
          candidate = document.at_css("meta[property='article:modified_time'], meta[name='last-modified'], time[datetime]")
          raw = candidate&.[]("content") || candidate&.[]("datetime")
          raw && Time.parse(raw)
        rescue ArgumentError, TypeError
          nil
        end

        def keyword_links(document, base_url)
          document.css("a[href]").filter_map do |link|
            label = clean(link.text)
            href = link["href"].to_s.strip
            combined = "#{label} #{href}"
            next unless combined.match?(KEYWORD_PATTERN)

            {label: label, href: absolute_url(href, base_url)}
          end
        end

        def keyword_excerpts(document)
          nodes = document.css("p, li, td, th, caption, article, section, div")
          nodes.filter_map do |node|
            text = clean(node.text)
            next if text.length < 15
            next unless text.match?(KEYWORD_PATTERN)

            text[0, 900]
          end.uniq.first(80)
        end

        def absolute_url(href, base_url)
          return href if href.match?(/\Ahttps?:\/\//i)
          return href unless base_url

          URI.join(base_url, href).to_s
        rescue URI::InvalidURIError
          href
        end

        def headings_section(headings)
          return if headings.empty?

          "Headings:\n#{headings.first(60).join("\n")}"
        end

        def links_section(links)
          return if links.empty?

          "Fire-related links:\n#{links.first(80).map { |link| "#{link[:label]} #{link[:href]}" }.join("\n")}"
        end

        def excerpts_section(excerpts)
          return if excerpts.empty?

          "Fire-related excerpts:\n#{excerpts.join("\n---\n")}"
        end

        def clean(text)
          text.to_s.gsub(/\s+/, " ").strip
        end
      end
    end
  end
end
