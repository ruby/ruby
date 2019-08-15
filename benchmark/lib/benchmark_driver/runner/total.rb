require 'benchmark_driver/struct'
require 'benchmark_driver/metric'
require 'benchmark_driver/default_job'
require 'benchmark_driver/default_job_parser'
require 'tempfile'

class BenchmarkDriver::Runner::Total
  METRIC = BenchmarkDriver::Metric.new(name: 'Total time', unit: 's', larger_better: false)

  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = Class.new(BenchmarkDriver::DefaultJob)
  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  JobParser = BenchmarkDriver::DefaultJobParser.for(klass: Job, metrics: [METRIC])

  # @param [BenchmarkDriver::Config::RunnerConfig] config
  # @param [BenchmarkDriver::Output] output
  # @param [BenchmarkDriver::Context] contexts
  def initialize(config:, output:, contexts:)
    @config = config
    @output = output
    @contexts = contexts
  end

  # This method is dynamically called by `BenchmarkDriver::JobRunner.run`
  # @param [Array<BenchmarkDriver::Runner::Total::Job>] jobs
  def run(jobs)
    if jobs.any? { |job| job.loop_count.nil? }
      raise 'missing loop_count is not supported in Ruby repository'
    end

    @output.with_benchmark do
      jobs.each do |job|
        @output.with_job(name: job.name) do
          job.runnable_contexts(@contexts).each do |context|
            duration = BenchmarkDriver::Repeater.with_repeat(config: @config, larger_better: false) do
              run_benchmark(job, context: context)
            end
            @output.with_context(name: context.name, executable: context.executable, gems: context.gems, prelude: context.prelude) do
              @output.report(values: { metric => duration }, duration: duration, loop_count: job.loop_count)
            end
          end
        end
      end
    end
  end

  private

  # @param [BenchmarkDriver::Runner::Ips::Job] job - loop_count is not nil
  # @param [BenchmarkDriver::Context] context
  # @return [BenchmarkDriver::Metrics]
  def run_benchmark(job, context:)
    benchmark = BenchmarkScript.new(
      preludes:   [context.prelude, job.prelude],
      script:     job.script,
      teardown:   job.teardown,
      loop_count: job.loop_count,
    )

    Tempfile.open(['benchmark_driver-', '.rb']) do |f|
      with_script(benchmark.render(result: f.path, target: target)) do |path|
        IO.popen([*context.executable.command, path], &:read) # TODO: print stdout if verbose=2
        if $?.success?
          Float(f.read)
        else
          BenchmarkDriver::Result::ERROR
        end
      end
    end
  end

  # This method is overridden by some subclasses
  def metric
    METRIC
  end

  # This method is overridden by some subclasses
  def target
    :total
  end

  def with_script(script)
    if @config.verbose >= 2
      sep = '-' * 30
      $stdout.puts "\n\n#{sep}[Script begin]#{sep}\n#{script}#{sep}[Script end]#{sep}\n\n"
    end

    Tempfile.open(['benchmark_driver-', '.rb']) do |f|
      f.puts script
      f.close
      return yield(f.path)
    end
  end

  # @param [String] prelude
  # @param [String] script
  # @param [String] teardown
  # @param [Integer] loop_count
  BenchmarkScript = ::BenchmarkDriver::Struct.new(:preludes, :script, :teardown, :loop_count) do
    # @param [String] result - A file to write result
    def render(result:, target:)
      prelude = preludes.reject(&:nil?).reject(&:empty?).join("\n")
      <<-RUBY
#{prelude}

require 'benchmark'
__bmdv_result = Benchmark.measure {
  #{while_loop(script, loop_count)}
}

#{teardown}

File.write(#{result.dump}, __bmdv_result.#{target})
      RUBY
    end

    private

    def while_loop(content, times)
      if !times.is_a?(Integer) || times <= 0
        raise ArgumentError.new("Unexpected times: #{times.inspect}")
      elsif times == 1
        return content
      end

      # TODO: execute in batch
      <<-RUBY
__bmdv_i = 0
while __bmdv_i < #{times}
  #{content}
  __bmdv_i += 1
end
      RUBY
    end
  end
  private_constant :BenchmarkScript
end
