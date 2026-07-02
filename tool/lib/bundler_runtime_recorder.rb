# frozen_string_literal: true

# Loaded into each parallel worker (via -r appended to RSPEC_EXECUTABLE by
# tool/lib/bundler_parallel_rspec.rb) to record per-example runtimes that the
# next run groups by. Kept in tool/ so recording does not depend on
# spec/bundler/spec_helper.rb (which is synced from rubygems/rubygems).

require_relative "bundler_runtime_grouping"

RSpec.configure do |config|
  config.before(:each) { @__runtime_start = Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  config.after(:each) do |example|
    next unless @__runtime_start
    BundlerRuntimeGrouping.record(example, Process.clock_gettime(Process::CLOCK_MONOTONIC) - @__runtime_start)
  end
end
