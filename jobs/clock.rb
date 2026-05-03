require_relative "../config/boot"
require_relative "fire_restriction_jobs"

interval = Integer(ENV.fetch("CLOCK_INTERVAL_SECONDS", "300"))

loop do
  warn "[clock] tick env=#{BFP.env}"
  BFP::FireRestrictions::PollDueSourcesJob.enqueue(Integer(ENV.fetch("FIRE_POLL_BATCH_SIZE", "25")))
  sleep interval
end
