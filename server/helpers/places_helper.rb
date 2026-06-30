module PlacesHelper
  def place_search_suggestions(query, limit: 8)
    require "bfp/places"

    BFP::Places::Searcher.new.search(query, limit: limit)
  rescue Sequel::DatabaseError, LoadError
    []
  end

  def trip_check_detail(slug)
    require "bfp/places"

    BFP::Places::TripCheckPresenter.new.check(slug)
  rescue Sequel::DatabaseError, LoadError
    nil
  end

  def trip_check_map(slug)
    require "bfp/places"

    BFP::Places::TripCheckPresenter.new.map(slug)
  rescue Sequel::DatabaseError, LoadError
    nil
  end

  def trip_check_search_results(query, limit: 8)
    place_search_suggestions(query, limit: limit)
  end

  def search_result_type_label(result)
    return "Fire restriction area" if result[:result_type].to_s == "land_unit"

    result[:place_type].to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end

  def search_result_rule_label(result)
    return "Area-wide page" if result[:result_type].to_s == "land_unit"

    "#{result[:matched_rule_count].to_i} matched"
  end

  def fire_use_rows(fire_use)
    [
      ["Campfires", fire_use[:campfire_policy]],
      ["Gas stoves", fire_use[:gas_stove_policy]],
      ["Liquid fuel stoves", fire_use[:liquid_fuel_stove_policy]],
      ["Alcohol stoves", fire_use[:alcohol_stove_policy]],
      ["Charcoal", fire_use[:charcoal_policy]],
      ["Solid fuel stoves", fire_use[:solid_fuel_stove_policy]],
      ["Wood stoves", fire_use[:wood_stove_policy]]
    ]
  end

  def confidence_label(value)
    percent = (value.to_f * 100).round
    "#{percent}%"
  end
end
