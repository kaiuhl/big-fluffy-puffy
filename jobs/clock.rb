require_relative "../config/boot"
require_relative "fire_restriction_jobs"

interval = Integer(ENV.fetch("CLOCK_INTERVAL_SECONDS", "300"))

loop do
  fire_auto_poll_enabled = ENV.fetch("FIRE_AUTO_POLL_ENABLED", "false") == "true"
  warn "[clock] tick env=#{BFP.env} fire_auto_poll_enabled=#{fire_auto_poll_enabled}"
  if fire_auto_poll_enabled
    BFP::FireRestrictions::PollDueSourcesJob.enqueue(Integer(ENV.fetch("FIRE_POLL_BATCH_SIZE", "25")))
  end
  sleep interval
end
