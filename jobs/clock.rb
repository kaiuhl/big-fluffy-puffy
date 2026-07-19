require_relative "../config/boot"
require_relative "fire_restriction_jobs"
require_relative "wildfire_jobs"

# The clock loop is a fast heartbeat; each pipeline gates its own cadence
# below. Do NOT slow the loop itself to throttle one pipeline (a weekly
# CLOCK_INTERVAL_SECONDS once froze wildfire sync for days) — throttle with
# FIRE_POLL_INTERVAL_MINUTES / WILDFIRE_POLL_INTERVAL_MINUTES instead.
interval = Integer(ENV.fetch("CLOCK_INTERVAL_SECONDS", "300"))

def fire_poll_due?
  minutes = Integer(ENV.fetch("FIRE_POLL_INTERVAL_MINUTES", "0"))
  return true if minutes <= 0

  latest = BFP::FireRestrictions::RestrictionSource.where(active: true).max(:last_checked_at)
  return true unless latest

  latest <= Time.now - (minutes * 60)
end

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
  if fire_auto_poll_enabled && fire_poll_due?
    BFP::FireRestrictions::PollDueSourcesJob.enqueue(Integer(ENV.fetch("FIRE_POLL_BATCH_SIZE", "25")))
  end
  if wildfire_poll_enabled && wildfire_sync_due?
    BFP::Wildfires::SyncJob.enqueue
  end
  sleep interval
end
