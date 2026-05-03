require_relative "../config/boot"
require_relative "fire_restriction_jobs"

BFP.db
Que.run!
