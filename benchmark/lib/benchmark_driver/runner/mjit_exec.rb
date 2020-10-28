require 'benchmark_driver/struct'
require 'benchmark_driver/metric'
require 'erb'

# A special runner dedicated for measuring mjit_exec overhead.
class BenchmarkDriver::Runner::MjitExec
  METRIC = BenchmarkDriver::Metric.new(name: 'Iteration per second', unit: 'i/s')

  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = ::BenchmarkDriver::Struct.new(
    :name,        # @param [String] name - This is mandatory for all runner
    :metrics,     # @param [Array<BenchmarkDriver::Metric>]
    :num_methods, # @param [Integer] num_methods - The number of methods to be defined
    :loop_count,  # @param [Integer] loop_count
    :from_jit,    # @param [TrueClass,FalseClass] from_jit - Whether the mjit_exec() is from JIT or not
    :to_jit,      # @param [TrueClass,FalseClass] to_jit - Whether the mjit_exec() is to JIT or not
  )
  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  class << JobParser = Module.new
    # @param [Array,String] num_methods
    # @param [Integer] loop_count
    # @param [TrueClass,FalseClass] from_jit
    # @param [TrueClass,FalseClass] to_jit
    def parse(num_methods:, loop_count:, from_jit:, to_jit:)
      if num_methods.is_a?(String)
        num_methods = eval(num_methods)
      end

      num_methods.map do |num|
        if num_methods.size > 1
          suffix = "[#{'%4d' % num}]"
        else
          suffix = "_#{num}"
        end
        Job.new(
          name: "mjit_exec_#{from_jit ? 'JT' : 'VM'}2#{to_jit ? 'JT' : 'VM'}#{suffix}",
          metrics: [METRIC],
          num_methods: num,
          loop_count: loop_count,
          from_jit: from_jit,
          to_jit: to_jit,
        )
      end
    end
  end

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
    @output.with_benchmark do
      jobs.each do |job|
        @output.with_job(name: job.name) do
          @contexts.each do |context|
            result = BenchmarkDriver::Repeater.with_repeat(config: @config, larger_better: true, rest_on_average: :average) do
              run_benchmark(job, context: context)
            end
            value, duration = result.value
            @output.with_context(name: context.name, executable: context.executable, gems: context.gems, prelude: context.prelude) do
              @output.report(values: { METRIC => value }, duration: duration, loop_count: job.loop_count)
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
    if job.from_jit
      if job.to_jit
        benchmark = BenchmarkJT2JT.new(num_methods: job.num_methods, loop_count: job.loop_count)
      else
        raise NotImplementedError, "JT2VM is not implemented yet"
      end
    else
      if job.to_jit
        benchmark = BenchmarkVM2JT.new(num_methods: job.num_methods, loop_count: job.loop_count)
      else
        benchmark = BenchmarkVM2VM.new(num_methods: job.num_methods, loop_count: job.loop_count)
      end
    end

    duration = Tempfile.open(['benchmark_driver-result', '.txt']) do |f|
      with_script(benchmark.render(result: f.path)) do |path|
        opt = []
        if context.executable.command.any? { |c| c.start_with?('--jit') }
          opt << '--jit-min-calls=2'
        end
        IO.popen([*context.executable.command, '--disable-gems', *opt, path], &:read)
        if $?.success?
          Float(f.read)
        else
          BenchmarkDriver::Result::ERROR
        end
      end
    end

    [job.loop_count.to_f / duration, duration]
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

  # @param [Integer] num_methods
  # @param [Integer] loop_count
  BenchmarkVM2VM = ::BenchmarkDriver::Struct.new(:num_methods, :loop_count) do
    # @param [String] result - A file to write result
    def render(result:)
      ERB.new(<<~EOS, trim_mode: '%').result(binding)
        % num_methods.times do |i|
        def a<%= i %>
          nil
        end
        % end
        RubyVM::MJIT.pause if RubyVM::MJIT.enabled?

        def vm
          t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          i = 0
          while i < <%= loop_count / 1000 %>
        % 1000.times do |i|
            a<%= i % num_methods %>
        % end
            i += 1
          end
        % (loop_count % 1000).times do |i|
          a<%= i % num_methods %>
        % end
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
        end

        vm # warmup call cache
        File.write(<%= result.dump %>, vm)
      EOS
    end
  end
  private_constant :BenchmarkVM2VM

  # @param [Integer] num_methods
  # @param [Integer] loop_count
  BenchmarkVM2JT = ::BenchmarkDriver::Struct.new(:num_methods, :loop_count) do
    # @param [String] result - A file to write result
    def render(result:)
      ERB.new(<<~EOS, trim_mode: '%').result(binding)
        % num_methods.times do |i|
        def a<%= i %>
          nil
        end
        a<%= i %>
        a<%= i %> # --jit-min-calls=2
        % end
        RubyVM::MJIT.pause if RubyVM::MJIT.enabled?

        def vm
          t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          i = 0
          while i < <%= loop_count / 1000 %>
        % 1000.times do |i|
            a<%= i % num_methods %>
        % end
            i += 1
          end
        % (loop_count % 1000).times do |i|
          a<%= i % num_methods %>
        % end
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
        end

        vm # warmup call cache
        File.write(<%= result.dump %>, vm)
      EOS
    end
  end
  private_constant :BenchmarkVM2JT

  # @param [Integer] num_methods
  # @param [Integer] loop_count
  BenchmarkJT2JT = ::BenchmarkDriver::Struct.new(:num_methods, :loop_count) do
    # @param [String] result - A file to write result
    def render(result:)
      ERB.new(<<~EOS, trim_mode: '%').result(binding)
        % num_methods.times do |i|
        def a<%= i %>
          nil
        end
        % end

        # You may need to:
        #   * Increase `JIT_ISEQ_SIZE_THRESHOLD` to 10000000 in mjit.h
        #   * Always return false in `inlinable_iseq_p()` of mjit_compile.c
        def jit
          t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          i = 0
          while i < <%= loop_count / 1000 %>
        % 1000.times do |i|
            a<%= i % num_methods %>
        % end
            i += 1
          end
        % (loop_count % 1000).times do |i|
          a<%= i % num_methods %>
        % end
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
        end

        jit
        jit
        RubyVM::MJIT.pause if RubyVM::MJIT.enabled?
        File.write(<%= result.dump %>, jit)
      EOS
    end
  end
  private_constant :BenchmarkJT2JT
end
