require_relative "../config/boot"

interval = Integer(ENV.fetch("CLOCK_INTERVAL_SECONDS", "300"))

loop do
  warn "[clock] tick env=#{BFP.env}"
  sleep interval
end
