ENV["APP_ENV"] ||= ENV.fetch("RACK_ENV", "development")
ENV["BRIDGETOWN_ENV"] ||= ENV["APP_ENV"]

require "bundler/setup"
require "json"

require "dotenv/load" unless ENV["APP_ENV"] == "production"

require "bridgetown"
require "que"
require "roda"
require "sequel"

module BFP
  def self.root
    File.expand_path("..", __dir__)
  end

  def self.env
    ENV.fetch("APP_ENV", "development")
  end

  def self.database_url
    if env == "test"
      ENV.fetch("TEST_DATABASE_URL", "postgres://bfp:bfp@localhost:5432/bfp_test")
    else
      ENV.fetch("DATABASE_URL", "postgres://bfp:bfp@localhost:5432/bfp_development")
    end
  end

  def self.db
    @db ||= Sequel.connect(database_url, max_connections: Integer(ENV.fetch("DB_POOL", "5"))).tap do |db|
      Que.connection = db
    end
  end
end

$LOAD_PATH.unshift(File.join(BFP.root, "lib"))
