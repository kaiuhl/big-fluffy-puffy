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

namespace :climate do
  def load_climate_normals
    require_relative "config/boot"
    require "bfp/climate"
  end

  desc "Import committed forest climate normals into Postgres"
  task :import_normals, [:csv_path, :manifest_path] do |_task, args|
    load_climate_normals

    importer = BFP::Climate::NormalImporter.new(
      csv_path: args[:csv_path] || BFP::Climate::NormalImporter::DEFAULT_CSV_PATH,
      manifest_path: args[:manifest_path] || BFP::Climate::NormalImporter::DEFAULT_MANIFEST_PATH
    )
    result = importer.import
    puts "Imported #{result.fetch(:rows)} climate normal rows for #{result.fetch(:dataset)}."
  end

  desc "Validate imported forest climate normals"
  task :validate_normals, [:dataset_slug] do |_task, args|
    load_climate_normals

    puts BFP::Climate::NormalValidator.new(
      dataset_slug: args[:dataset_slug] || BFP::Climate::NormalValidator::DEFAULT_DATASET_SLUG
    ).report
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

  namespace :localized do
    desc "Seed curated localized camping and backpacking fire-use rules"
    task :seed do
      load_fire_restrictions

      counts = BFP::FireRestrictions::CuratedRuleSeeder.new.seed
      puts "Seeded #{counts[:rules]} localized rules and #{counts[:areas]} restriction areas."
      puts "#{counts[:changed_rules]} localized rules changed and need review." if counts[:changed_rules].positive?
    end
  end

  desc "Seed fire restriction sources and curated localized fire-use rules"
  task :seed do
    Rake::Task["fire:sources:seed"].invoke
    Rake::Task["fire:localized:seed"].invoke
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

    desc "Auto-accept validated official observations that satisfy publication rules"
    task :auto_accept do
      load_fire_restrictions

      policy = BFP::FireRestrictions::AutoReviewPolicy.new
      resolver = BFP::FireRestrictions::Resolver.new
      accepted = []

      BFP::FireRestrictions::RestrictionObservation
        .where(review_status: "needs_review")
        .all
        .each do |observation|
          next unless policy.review_status_for_observation(observation) == "auto_accepted"

          observation.update(review_status: "auto_accepted")
          accepted << observation
        end

      accepted.map(&:land_unit).uniq.each { |land_unit| resolver.resolve(land_unit) }

      puts "Auto-accepted #{accepted.length} observations."
      accepted.each do |observation|
        puts [
          observation.id,
          observation.land_unit.name,
          observation.restriction_source.slug,
          observation.status,
          "confidence=#{observation.confidence}"
        ].join(" | ")
      end
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

  namespace :map do
    desc "Refresh curated USFS forest boundary GeoJSON for the fire restrictions map"
    task :refresh_boundaries do
      require_relative "config/boot"
      require "bfp/fire_restrictions/boundary_refresher"

      count = BFP::FireRestrictions::BoundaryRefresher.new.refresh
      puts "Refreshed #{count} fire restriction map boundaries."
    end
  end
end

namespace :places do
  def load_places
    require_relative "config/boot"
    require "bfp/places"
  end

  desc "Import configured place datasets into Postgres"
  task :import do
    load_places

    counts = BFP::Places::Importer.new.import
    puts "Imported #{counts[:places]} places and #{counts[:names]} names from #{counts[:datasets]} place datasets."
  end

  desc "Seed BFP-curated destinations and localized restriction areas"
  task :seed_manual do
    load_places

    counts = BFP::Places::ManualSeeder.new.seed
    puts "Seeded #{counts[:places]} manual places, #{counts[:localized_areas]} localized restriction areas, and #{counts[:names]} names."
  end

  desc "Resolve places against monitored forests and localized restriction geometry"
  task :resolve do
    load_places

    counts = BFP::Places::Resolver.new.resolve
    puts "Resolved #{counts[:land_unit_matches]} forest matches and #{counts[:localized_rule_matches]} localized rule matches."
  end

  desc "Import, seed, and resolve BFP place search data"
  task :refresh do
    Rake::Task["places:import"].invoke
    Rake::Task["places:seed_manual"].invoke
    Rake::Task["places:resolve"].invoke
  end
end
