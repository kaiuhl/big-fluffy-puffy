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
