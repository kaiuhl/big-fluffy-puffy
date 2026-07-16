require_relative "../config/boot"
require_relative "fire_restriction_jobs"
require_relative "wildfire_jobs"

interval = Integer(ENV.fetch("CLOCK_INTERVAL_SECONDS", "300"))

def wildfire_sync_due?
  minutes = Integer(ENV.fetch("WILDFIRE_POLL_INTERVAL_MINUTES", "45"))
  latest = BFP::Wildfires::WildfireSync.reverse(:started_at).first
  return true unless latest&.started_at

  latest.started_at <= Time.now - (minutes * 60)
end

loop do
  fire_auto_poll_enabled = ENV.fetch("FIRE_AUTO_POLL_ENABLED", "false") == "true"
  wildfire_poll_enabled = ENV.fetch("WILDFIRE_POLL_ENABLED", "false") == "true"
  warn "[clock] tick env=#{BFP.env} fire_auto_poll_enabled=#{fire_auto_poll_enabled} wildfire_poll_enabled=#{wildfire_poll_enabled}"
  if fire_auto_poll_enabled
    BFP::FireRestrictions::PollDueSourcesJob.enqueue(Integer(ENV.fetch("FIRE_POLL_BATCH_SIZE", "25")))
  end
  if wildfire_poll_enabled && wildfire_sync_due?
    BFP::Wildfires::SyncJob.enqueue
  end
  sleep interval
end
