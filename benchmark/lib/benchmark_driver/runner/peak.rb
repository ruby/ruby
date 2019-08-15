require 'benchmark_driver/struct'
require 'benchmark_driver/metric'
require 'benchmark_driver/default_job'
require 'benchmark_driver/default_job_parser'
require 'tempfile'

class BenchmarkDriver::Runner::Peak
  METRIC = BenchmarkDriver::Metric.new(
    name: 'Peak memory usage', unit: 'bytes', larger_better: false, worse_word: 'larger',
  )

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
  # @param [Array<BenchmarkDriver::Runner::Peak::Job>] jobs
  def run(jobs)
    if jobs.any? { |job| job.loop_count.nil? }
      jobs = jobs.map do |job|
        job.loop_count ? job : Job.new(job.to_h.merge(loop_count: 1))
      end
    end

    @output.with_benchmark do
      jobs.each do |job|
        @output.with_job(name: job.name) do
          job.runnable_contexts(@contexts).each do |context|
            value = BenchmarkDriver::Repeater.with_repeat(config: @config, larger_better: false) do
              run_benchmark(job, context: context)
            end
            @output.with_context(name: context.name, executable: context.executable, gems: context.gems, prelude: context.prelude) do
              @output.report(values: { metric => value }, loop_count: job.loop_count)
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

    memory_status = File.expand_path('../../../../tool/lib/memory_status', __dir__)
    Tempfile.open(['benchmark_driver-', '.rb']) do |f|
      with_script(benchmark.render) do |path|
        output = IO.popen([*context.executable.command, path, f.path, target, memory_status], &:read)
        if $?.success?
          Integer(f.read)
        else
          $stdout.print(output)
          BenchmarkDriver::Result::ERROR
        end
      end
    end
  end

  # Overridden by BenchmarkDriver::Runner::Size
  def target
    'peak'
  end

  # Overridden by BenchmarkDriver::Runner::Size
  def metric
    METRIC
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
    def render
      prelude = preludes.reject(&:nil?).reject(&:empty?).join("\n")
      <<-RUBY
#{prelude}
#{while_loop(script, loop_count)}
#{teardown}

result_file, target, memory_status = ARGV
require_relative memory_status

ms = Memory::Status.new
case target.to_sym
when :peak
  key = ms.respond_to?(:hwm) ? :hwm : :peak
when :size
  key = ms.respond_to?(:rss) ? :rss : :size
else
  raise('unexpected target: ' + target)
end

File.write(result_file, ms[key])
      RUBY
    end

    private

    def while_loop(content, times)
      if !times.is_a?(Integer) || times <= 0
        raise ArgumentError.new("Unexpected times: #{times.inspect}")
      end

      if times > 1
        <<-RUBY
__bmdv_i = 0
while __bmdv_i < #{times}
  #{content}
  __bmdv_i += 1
end
        RUBY
      else
        content
      end
    end
  end
  private_constant :BenchmarkScript
end
