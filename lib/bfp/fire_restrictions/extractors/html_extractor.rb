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
          alert_summary = forest_alert_summary(document)
          body_text = clean((document.at_css("main") || document.at_css("body") || document).text)

          extracted_text = [
            ("Title: #{title}" if title),
            ("Canonical URL: #{canonical_url}" if canonical_url),
            ("Modified: #{modified_at.iso8601}" if modified_at),
            headings_section(headings),
            links_section(links),
            alert_summary_section(alert_summary),
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
              forest_alert_summary: alert_summary,
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

        def forest_alert_summary(document)
          forest_alerts = section_alerts(document, "Forest Alerts")
          return {} if forest_alerts.empty?

          fire_restriction_alerts = forest_alerts.select { |alert| fire_restriction_alert?(alert) }
          {
            forest_alerts_count: forest_alerts.length,
            forest_alert_titles: forest_alerts.map { |alert| alert[:title] }.first(40),
            fire_restriction_alerts_count: fire_restriction_alerts.length,
            fire_restriction_alerts: fire_restriction_alerts.first(20)
          }
        end

        def section_alerts(document, heading_text)
          nodes = document.css("h1, h2, h3, h4, h5, h6, p, li").to_a
          heading_index = nodes.index { |node| clean(node.text).casecmp?(heading_text) }
          return [] unless heading_index

          alerts = []
          nodes[(heading_index + 1)..]&.each_with_index do |node, offset|
            break if major_heading?(node)
            next unless node.name.match?(/\Ah[3-6]\z/i)

            title = clean(node.text)
            next if title.empty? || title.match?(/\AFilter & Sort Alerts\z/i)

            details = alert_card_text(node) || following_detail_text(nodes, heading_index + 1 + offset)
            alerts << {title: title, text: clean([title, details].join(" "))}
          end
          alerts
        end

        def alert_card_text(node)
          card = node.ancestors.find { |ancestor| ancestor.name == "li" && ancestor["class"].to_s.include?("usa-card") }
          text = clean(card&.text)
          text unless text.empty?
        end

        def following_detail_text(nodes, start_index)
          details = []
          nodes[(start_index + 1)..]&.each do |sibling|
            break if sibling.name.match?(/\Ah[1-6]\z/i)

            text = clean(sibling.text)
            details << text unless text.empty?
          end
          details.join(" ")
        end

        def major_heading?(node)
          return false unless node.name.match?(/\Ah[12]\z/i)

          !clean(node.text).match?(/\AForest Alerts\z/i)
        end

        def fire_restriction_alert?(alert)
          text = alert.fetch(:text).to_s
          return false if text.match?(/fireworks|explosives|exploding targets|prescribed fire|fire danger|smoke map|burned area|fire closure/i)

          text.match?(/fire restrictions?|campfires?|camp fire|public use restrictions?|wood[- ]fire|stove fire|open fires?|fire prohibition|building, maintaining, attending.*fire/i)
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

        def alert_summary_section(summary)
          return if summary.empty?

          lines = ["Forest Alert Summary:"]
          lines << "Forest alerts listed: #{summary.fetch(:forest_alerts_count)}"
          if summary.fetch(:fire_restriction_alerts_count).zero?
            lines << "No active forest fire restriction alerts were listed in the Forest Alerts section."
          else
            lines << "Forest fire restriction alerts listed:"
            summary.fetch(:fire_restriction_alerts).each do |alert|
              lines << "#{alert.fetch(:title)}: #{alert.fetch(:text)[0, 700]}"
            end
          end
          lines.join("\n")
        end

        def excerpts_section(excerpts)
          return if excerpts.empty?

          "Fire-related excerpts:\n#{excerpts.join("\n---\n")}"
        end

        def clean(text)
          text.to_s.tr("\u00a0", " ").gsub(/\s+/, " ").strip
        end
      end
    end
  end
end
