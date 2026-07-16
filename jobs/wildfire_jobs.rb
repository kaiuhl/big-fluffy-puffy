require_relative "../config/boot"
require "bfp/wildfires"

module BFP
  module Wildfires
    class SyncJob < Que::Job
      def self.perform_now
        Sync.new.run
      end

      def run
        self.class.perform_now
      end
    end
  end
end
