require 'benchmark_driver/runner/total'

class BenchmarkDriver::Runner::Cstime < BenchmarkDriver::Runner::Total
  METRIC = BenchmarkDriver::Metric.new(name: 'cstime', unit: 's', larger_better: false)

  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = Class.new(BenchmarkDriver::DefaultJob)
  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  JobParser = BenchmarkDriver::DefaultJobParser.for(klass: Job, metrics: [METRIC])

  private

  # Overriding BenchmarkDriver::Runner::Total#metric
  def metric
    METRIC
  end

  # Overriding BenchmarkDriver::Runner::Total#target
  def target
    :cstime
  end
end
