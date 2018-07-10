require 'benchmark_driver/runner/peak'

# Actually the same as BenchmarkDriver::Runner::Memory
class BenchmarkDriver::Runner::Size < BenchmarkDriver::Runner::Peak
  METRIC = BenchmarkDriver::Metric.new(
    name: 'Max resident set size', unit: 'bytes', larger_better: false, worse_word: 'larger',
  )

  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = Class.new(BenchmarkDriver::DefaultJob)
  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  JobParser = BenchmarkDriver::DefaultJobParser.for(klass: Job, metrics: [METRIC])

  private

  # Overriding BenchmarkDriver::Runner::Peak#metric
  def metric
    METRIC
  end

  # Overriding BenchmarkDriver::Runner::Peak#target
  def target
    'size'
  end
end
