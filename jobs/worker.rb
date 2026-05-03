worker_count = ENV.fetch("QUE_WORKER_COUNT", "2")
poll_interval = ENV.fetch("QUE_POLL_INTERVAL_SECONDS", "5")

exec(
  "bundle",
  "exec",
  "que",
  "--worker-count",
  worker_count,
  "--poll-interval",
  poll_interval,
  "./jobs/fire_restriction_jobs"
)
