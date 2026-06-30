require_relative "../config/boot"
require_relative "view_renderer"
require_relative "helpers/fire_restrictions_helper"
require_relative "helpers/places_helper"
require_relative "helpers/seo_helper"
require_relative "routes/api"
require_relative "routes/fire_restrictions"
require_relative "routes/pages"
require_relative "routes/site_meta"
require_relative "routes/trip_checks"
require "bfp/climate/low_sparkline"
require "bfp/fire_restrictions/fire_use_sparkline"
require "bfp/fire_restrictions/status_display"
require "time"

class RodaApp < Roda
  NAV_LINKS = [
    {href: "/fire-restrictions", label: "Fire Restrictions"},
    {href: "/why-fireless", label: "Why Fireless"},
    {href: "/about", label: "About"},
    {href: "/contact", label: "Contact"}
  ].freeze
  SITE_CSS_PATH = "/styles/site.css?v=20260630-forest-summary-tone".freeze
  FIRE_RESTRICTIONS_JS_PATH = "/scripts/fire-restrictions.js?v=20260630-forestwide-map".freeze
  PLACE_SEARCH_JS_PATH = "/scripts/place-search.js?v=20260630-unified-search-1".freeze

  STATE_NAMES = {
    "or" => "Oregon",
    "wa" => "Washington",
    "ca" => "California",
    "other" => "Other"
  }.freeze
  STATE_ORDER = %w[or wa ca other].freeze
  STATE_BY_MARKET_BUCKET = {
    "oregon" => "or",
    "washington" => "wa",
    "northern_california" => "ca",
    "extended_tahoe" => "ca"
  }.freeze
  STATE_BY_LAND_UNIT_SLUG = {
    "colville" => "wa",
    "deschutes" => "or",
    "fremont-winema" => "or",
    "gifford-pinchot" => "wa",
    "malheur" => "or",
    "mt-baker-snoqualmie" => "wa",
    "mt-hood" => "or",
    "ochoco-crooked-river" => "or",
    "okanogan-wenatchee" => "wa",
    "olympic" => "wa",
    "rogue-river-siskiyou" => "or",
    "siuslaw" => "or",
    "umatilla" => "or",
    "umpqua" => "or",
    "wallowa-whitman" => "or",
    "willamette" => "or",
    "north-cascades" => "wa",
    "mount-rainier" => "wa",
    "olympic-national-park" => "wa",
    "crater-lake" => "or",
    "klamath" => "ca",
    "six-rivers" => "ca",
    "shasta-trinity" => "ca",
    "mendocino" => "ca",
    "modoc" => "ca",
    "lassen" => "ca",
    "lassen-volcanic" => "ca",
    "plumas" => "ca",
    "tahoe" => "ca",
    "eldorado" => "ca",
    "lake-tahoe-basin" => "ca"
  }.freeze

  include ViewRenderer
  include FireRestrictionsHelper
  include PlacesHelper
  include SeoHelper
  include ApiRoutes
  include FireRestrictionsRoutes
  include SiteMetaRoutes
  include TripCheckRoutes
  include PageRoutes

  opts[:root] = BFP.root

  plugin :common_logger
  plugin :head
  plugin :public

  route do |r|
    r.public

    r.get "health" do
      json_response({status: "ok"})
    end

    route_api(r)
    route_fire_restrictions(r)
    route_trip_checks(r)
    route_site_meta(r)
    route_pages(r)
  end
end
