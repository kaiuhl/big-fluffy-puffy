require_relative "../spec_helper"

RSpec.describe "jobs/worker.rb" do
  # worker.rb execs the que CLI on load, so assert on its source: every job
  # file the clock can enqueue must also be loaded by the worker, or those
  # jobs fail with NameError at run time.
  it "loads every job file the clock enqueues from" do
    worker_source = File.read(File.expand_path("../../jobs/worker.rb", __dir__), encoding: "UTF-8")
    clock_source = File.read(File.expand_path("../../jobs/clock.rb", __dir__), encoding: "UTF-8")

    clock_source.scan(%r{require_relative "(\w+_jobs)"}).flatten.each do |job_file|
      expect(worker_source).to include("./jobs/#{job_file}"),
        "jobs/worker.rb must load ./jobs/#{job_file} or its jobs raise NameError in the worker"
    end
  end
end
