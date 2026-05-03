ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["BRIDGETOWN_ENV"] = "test"

require "rack/test"
require "rspec"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
