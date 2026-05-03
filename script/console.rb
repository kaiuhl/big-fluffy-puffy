# frozen_string_literal: true

ENV["APP_ENV"] ||= ENV.fetch("RACK_ENV", "development")
ENV["BRIDGETOWN_ENV"] ||= ENV["APP_ENV"]

require "irb"
require "pp"
require_relative "../config/boot"

begin
  require "bfp/fire_restrictions"
rescue Sequel::DatabaseConnectionError => error
  warn "Fire restriction models were not loaded because the database is unavailable:"
  warn "#{error.class}: #{error.message.lines.first&.strip}"
end

module BFPConsoleHelpers
  def app_env
    BFP.env
  end

  def database_url
    BFP.database_url
  end

  def fire_loaded?
    !!defined?(BFP::FireRestrictions::LandUnit)
  end

  def fire_counts
    ensure_fire_loaded!

    {
      land_units: BFP::FireRestrictions::LandUnit.count,
      active_land_units: BFP::FireRestrictions::LandUnit.where(active: true).count,
      sources: BFP::FireRestrictions::RestrictionSource.count,
      active_sources: BFP::FireRestrictions::RestrictionSource.where(active: true).count,
      fetches: BFP::FireRestrictions::SourceFetch.count,
      documents: BFP::FireRestrictions::SourceDocument.count,
      observations: BFP::FireRestrictions::RestrictionObservation.count,
      statuses: BFP::FireRestrictions::RestrictionStatus.count
    }
  end

  def forests
    ensure_fire_loaded!

    BFP::FireRestrictions::StatusPresenter.new.forests
  end

  def forest(slug)
    ensure_fire_loaded!

    BFP::FireRestrictions::LandUnit.first(slug: slug.to_s)
  end

  def source(slug)
    ensure_fire_loaded!

    BFP::FireRestrictions::RestrictionSource.first(slug: slug.to_s)
  end

  def status(slug)
    forest(slug)&.restriction_status
  end

  def latest_fetches(limit = 10)
    ensure_fire_loaded!

    BFP::FireRestrictions::SourceFetch.reverse(:id).limit(limit).all.map do |fetch|
      {
        id: fetch.id,
        source: fetch.restriction_source&.slug,
        http_status: fetch.http_status,
        changed: fetch.content_changed,
        error_class: fetch.error_class,
        fetched_at: fetch.fetched_at
      }
    end
  end

  def latest_observations(limit = 10)
    ensure_fire_loaded!

    BFP::FireRestrictions::RestrictionObservation.reverse(:id).limit(limit).all.map do |observation|
      {
        id: observation.id,
        land_unit: observation.land_unit&.slug,
        source: observation.restriction_source&.slug,
        status: observation.status,
        campfire_policy: observation.campfire_policy,
        review_status: observation.review_status,
        confidence: observation.confidence,
        created_at: observation.created_at
      }
    end
  end

  def review_queue(limit = 20, status: nil, land_unit: nil)
    ensure_fire_loaded!

    BFP::FireRestrictions::ReviewPresenter.new.queue(limit: limit, status: status, land_unit: land_unit)
  end

  def review_observation(id)
    ensure_fire_loaded!

    BFP::FireRestrictions::ReviewPresenter.new.detail(id)
  end

  def accept_observation(id)
    ensure_fire_loaded!

    observation = BFP::FireRestrictions::RestrictionObservation[Integer(id)]
    raise "Unknown observation: #{id}" unless observation

    observation.update(review_status: "accepted")
    BFP::FireRestrictions::Resolver.new.resolve(observation.land_unit)

    {
      accepted_observation_id: observation.id,
      forest: observation.land_unit.name,
      public_status: status(observation.land_unit.slug)&.status,
      public_campfire_policy: status(observation.land_unit.slug)&.campfire_policy
    }
  end

  def reject_observation(id, reason = nil)
    ensure_fire_loaded!

    observation = BFP::FireRestrictions::RestrictionObservation[Integer(id)]
    raise "Unknown observation: #{id}" unless observation

    reasons = Array(observation.needs_review_reasons)
    reasons << "Reviewer rejected: #{reason}" if reason.to_s.strip != ""
    observation.update(
      review_status: "rejected",
      needs_review_reasons: BFP::FireRestrictions::Jsonb.wrap(reasons)
    )
    BFP::FireRestrictions::Resolver.new.resolve(observation.land_unit)

    {
      rejected_observation_id: observation.id,
      forest: observation.land_unit.name,
      public_status: status(observation.land_unit.slug)&.status
    }
  end

  def llm_costs(limit = 20)
    ensure_fire_loaded!

    rows = BFP::FireRestrictions::RestrictionObservation.reverse(:id).all.filter_map do |observation|
      raw_output = observation.raw_output || {}
      usage = raw_output["llm_usage"]
      next unless usage

      {
        id: observation.id,
        land_unit: observation.land_unit&.slug,
        source: observation.restriction_source&.slug,
        model: observation.parser_model_id,
        input_tokens: usage.fetch("input_tokens", 0),
        output_tokens: usage.fetch("output_tokens", 0),
        estimated_cost_usd: raw_output["llm_cost_estimate_usd"].to_f,
        created_at: observation.created_at
      }
    end

    {
      observations: rows.length,
      input_tokens: rows.sum { |row| row.fetch(:input_tokens).to_i },
      output_tokens: rows.sum { |row| row.fetch(:output_tokens).to_i },
      estimated_cost_usd: rows.sum { |row| row.fetch(:estimated_cost_usd).to_f }.round(6),
      recent: rows.first(limit)
    }
  end

  def help!
    puts <<~HELP
      BFP console helpers:
        app_env
        database_url
        fire_counts
        forests
        forest("deschutes")
        source("willamette-fire-info")
        status("deschutes")
        latest_fetches
        latest_observations
        review_queue
        review_queue(20, status: "partial")
        review_observation(123)
        accept_observation(123)
        reject_observation(123, "reason")
        llm_costs
    HELP
  end

  private

  def ensure_fire_loaded!
    return if fire_loaded?

    raise "Fire restriction models are not loaded. Start Postgres or check DATABASE_URL."
  end
end

TOPLEVEL_BINDING.receiver.extend(BFPConsoleHelpers)

if ARGV.first == "-e" || ARGV.first == "--eval"
  expression = ARGV[1]
  abort "Usage: bin/console -e 'fire_counts'" unless expression

  pp TOPLEVEL_BINDING.eval(expression)
  exit
end

puts "BFP console (#{BFP.env})"
if TOPLEVEL_BINDING.receiver.fire_loaded?
  puts "Fire restriction models loaded."
else
  puts "Fire restriction models not loaded."
end
puts "Run help! for helpers."

IRB.start(__FILE__)
