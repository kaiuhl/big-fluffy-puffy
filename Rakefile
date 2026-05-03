require "bundler/setup"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :db do
  desc "Run Sequel migrations"
  task :migrate do
    require_relative "config/boot"
    require "sequel/extensions/migration"

    Sequel::Migrator.run(BFP.db, File.join(BFP.root, "db/migrations"))
  end
end

namespace :que do
  desc "Install or update Que database schema"
  task :migrate do
    require_relative "config/boot"

    BFP.db
    Que.migrate!(version: 7)
  end
end

namespace :fire do
  def load_fire_restrictions
    require_relative "config/boot"
    require "bfp/fire_restrictions"
  end

  namespace :sources do
    desc "Seed fire restriction land units and source URLs"
    task :seed do
      load_fire_restrictions

      counts = BFP::FireRestrictions::SourceSeeder.new.seed
      puts "Seeded #{counts[:land_units]} land units and #{counts[:sources]} sources."
    end
  end

  desc "Poll all due fire restriction sources synchronously"
  task :poll_due do
    load_fire_restrictions

    fetches = BFP::FireRestrictions::Poller.new.poll_due
    puts "Polled #{fetches.length} due sources."
  end

  desc "Poll one fire restriction source by source slug"
  task :poll, [:source_slug] do |_task, args|
    load_fire_restrictions

    raise "Usage: rake fire:poll[source_slug]" unless args[:source_slug]

    fetch = BFP::FireRestrictions::Poller.new.poll_source_slug(args[:source_slug])
    puts "Polled #{args[:source_slug]}: HTTP #{fetch.http_status || fetch.error_class} changed=#{fetch.content_changed}"
  end

  namespace :review do
    desc "List best fire restriction review candidates by forest"
    task :candidates, [:limit] do |_task, args|
      load_fire_restrictions

      limit = args[:limit] ? Integer(args[:limit]) : nil
      puts BFP::FireRestrictions::ReviewPresenter.new.format_candidates(limit: limit)
    end

    desc "List fire restriction observations awaiting review"
    task :list, [:limit] do |_task, args|
      load_fire_restrictions

      puts BFP::FireRestrictions::ReviewPresenter.new.format_queue(limit: args[:limit] || 50)
    end

    desc "List review observations for one forest, ranked by likely usefulness"
    task :forest, [:land_unit_slug] do |_task, args|
      load_fire_restrictions

      raise "Usage: rake fire:review:forest[land_unit_slug]" unless args[:land_unit_slug]

      puts BFP::FireRestrictions::ReviewPresenter.new.format_forest(args[:land_unit_slug])
    end

    desc "Show one parsed fire restriction observation"
    task :show, [:observation_id] do |_task, args|
      load_fire_restrictions

      raise "Usage: rake fire:review:show[observation_id]" unless args[:observation_id]

      puts BFP::FireRestrictions::ReviewPresenter.new.format_detail(args[:observation_id])
    end

    desc "Accept a parsed fire restriction observation and resolve the public status"
    task :accept, [:observation_id] do |_task, args|
      load_fire_restrictions

      raise "Usage: rake fire:review:accept[observation_id]" unless args[:observation_id]

      observation = BFP::FireRestrictions::RestrictionObservation[Integer(args[:observation_id])]
      raise "Unknown observation: #{args[:observation_id]}" unless observation

      observation.review_status = "accepted"
      observation.save
      BFP::FireRestrictions::Resolver.new.resolve(observation.land_unit)
      puts "Accepted observation #{observation.id} for #{observation.land_unit.name}."
    end

    desc "Reject a parsed fire restriction observation and resolve the public status"
    task :reject, [:observation_id, :reason] do |_task, args|
      load_fire_restrictions

      raise "Usage: rake fire:review:reject[observation_id,reason]" unless args[:observation_id]

      observation = BFP::FireRestrictions::RestrictionObservation[Integer(args[:observation_id])]
      raise "Unknown observation: #{args[:observation_id]}" unless observation

      reasons = Array(observation.needs_review_reasons)
      reasons << "Reviewer rejected: #{args[:reason]}" if args[:reason].to_s.strip != ""
      observation.update(
        review_status: "rejected",
        needs_review_reasons: BFP::FireRestrictions::Jsonb.wrap(reasons)
      )
      BFP::FireRestrictions::Resolver.new.resolve(observation.land_unit)
      puts "Rejected observation #{observation.id} for #{observation.land_unit.name}."
    end
  end

  namespace :status do
    desc "List resolved public fire restriction statuses"
    task :list do
      load_fire_restrictions

      BFP::FireRestrictions::StatusPresenter.new.forests.each do |forest|
        puts [
          forest[:name],
          forest[:status],
          forest[:campfire_policy],
          "review=#{forest[:review_status]}",
          "checked=#{forest[:last_checked_at] || "never"}"
        ].join(" | ")
      end
    end
  end
end
