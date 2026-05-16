module FireRestrictionsHelper
  def site_nav_links
    self.class::NAV_LINKS
  end

  def active_brand?(current_path)
    current_path == "/"
  end

  def active_nav?(link, current_path)
    link.fetch(:href) == current_path
  end

  def fire_restriction_records
    require "bfp/fire_restrictions"

    BFP::FireRestrictions::StatusPresenter.new.forests
  rescue Sequel::DatabaseError, LoadError
    []
  end

  def fire_restriction_map
    require "bfp/fire_restrictions/map_presenter"

    BFP::FireRestrictions::MapPresenter.new(records: fire_restriction_records).geojson
  rescue Sequel::DatabaseError, LoadError
    {type: "FeatureCollection", features: []}
  end

  def forest_fire_restriction_detail(slug)
    require "bfp/fire_restrictions/forest_status_presenter"

    BFP::FireRestrictions::ForestStatusPresenter.new.forest(slug)
  rescue Sequel::DatabaseError, LoadError
    nil
  end

  def forest_fire_restriction_map(slug)
    require "bfp/fire_restrictions/forest_map_presenter"

    BFP::FireRestrictions::ForestMapPresenter.new(slug: slug).geojson
  rescue Sequel::DatabaseError, LoadError
    nil
  end

  def partition_fire_restrictions(records)
    records.each_with_object({active: [], none: [], unknown: []}) do |forest, groups|
      if published_status?(forest) && forest[:status].to_s == "none"
        groups[:none] << forest
      elsif published_status?(forest) && forest[:status].to_s != "unknown"
        groups[:active] << forest
      else
        groups[:unknown] << forest
      end
    end
  end

  def published_status?(forest)
    %w[accepted auto_accepted].include?(forest[:review_status].to_s)
  end

  def climate_low_column_label(records)
    month_name = records
      .filter_map { |forest| forest.dig(:climate_low_context, :month_name).to_s.strip }
      .find { |name| !name.empty? }

    month_name ? "Typical #{month_name} lows" : "Typical lows"
  end

  def region_state_sorted_records(records)
    records.sort_by do |forest|
      state = state_code(forest)
      [self.class::STATE_ORDER.index(state) || self.class::STATE_ORDER.length, forest[:name].to_s]
    end
  end

  def region_state_label(forest)
    region = forest[:region_code].to_s
    state = self.class::STATE_NAMES.fetch(state_code(forest))

    [region, state].reject(&:empty?).join(" / ")
  end

  def state_code(forest)
    self.class::STATE_BY_LAND_UNIT_SLUG.fetch(forest[:slug].to_s) do
      self.class::STATE_BY_MARKET_BUCKET.fetch(forest[:market_bucket].to_s, "other")
    end
  end

  def preferred_source(forest)
    if forest[:source_url]
      return {
        url: forest[:source_url],
        name: forest[:source_title] || "Current evidence",
        last_checked_at: forest[:last_checked_at]
      }
    end

    sources = Array(forest[:sources])
    sources.min_by { |source| [source_rank(source), source[:name].to_s] }
  end

  def source_rank(source)
    {
      "fs_fire_info_page" => 0,
      "fs_fire_page" => 1,
      "fs_alerts_page" => 2,
      "fs_release_page" => 3
    }.fetch(source[:source_type].to_s, 9)
  end

  def checked_at_for(forest, source)
    forest[:last_checked_at] || source&.fetch(:last_checked_at, nil)
  end

  def date_label(value)
    BFP::FireRestrictions::StatusDisplay.checked_date_label(value)
  end

  def campfire_policy_for(forest)
    BFP::FireRestrictions::StatusDisplay.campfire_policy(
      status: forest[:status],
      campfire_policy: forest[:campfire_policy]
    )
  end

  def restriction_note(forest)
    summary = forest[:summary].to_s.strip
    return summary unless summary.empty?

    evidence = Array(forest[:evidence_quotes]).find { |quote| !quote.to_s.strip.empty? }
    return evidence if evidence

    published_status?(forest) ? "Published source reviewed." : "Needs source review."
  end

  def climate_low_available?(forest)
    !Array(forest.dig(:climate_low_context, :bands)).empty?
  end

  def climate_low_sparkline(forest)
    return "" unless climate_low_available?(forest)

    BFP::Climate::LowSparkline.render(forest[:climate_low_context])
  end

  def policy_label(value)
    BFP::FireRestrictions::StatusDisplay.policy_label(value)
  end

  def stove_policy_label(value, shutoff_required: nil)
    BFP::FireRestrictions::StatusDisplay.stove_policy_label(value, shutoff_required: shutoff_required)
  end

  def duration_label(rule)
    BFP::FireRestrictions::StatusDisplay.duration_label(rule)
  end

  def labelize(value)
    value.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def forest_count(count)
    "#{count} #{(count == 1) ? "forest" : "forests"}"
  end

  def h(value)
    Rack::Utils.escape_html(value.to_s)
  end
end
