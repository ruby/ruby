require 'erb'

# A runner to measure performance *inside* Ractor
class BenchmarkDriver::Runner::Ractor < BenchmarkDriver::Runner::Ips
  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = Class.new(BenchmarkDriver::DefaultJob) do
    attr_accessor :ractor
  end

  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  JobParser = BenchmarkDriver::DefaultJobParser.for(klass: Job, metrics: [METRIC]).extend(Module.new{
    def parse(ractor: 1, **kwargs)
      super(**kwargs).each do |job|
        job.ractor = ractor
      end
    end
  })

  private

  unless private_instance_methods.include?(:run_benchmark)
    raise "#run_benchmark is no longer defined in BenchmarkDriver::Runner::Ips"
  end

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

    results = job.ractor.times.map do
      Tempfile.open('benchmark_driver_result')
    end
    duration = with_script(benchmark.render(results: results.map(&:path))) do |path|
      success = execute(*context.executable.command, path, exception: false)
      if success && ((value = results.map { |f| Float(f.read) }.max) > 0)
        value
      else
        BenchmarkDriver::Result::ERROR
      end
    end
    results.each(&:close)

    value_duration(
      loop_count: job.loop_count,
      duration: duration,
    )
  end

  # @param [String] prelude
  # @param [String] script
  # @param [String] teardown
  # @param [Integer] loop_count
  BenchmarkScript = ::BenchmarkDriver::Struct.new(:preludes, :script, :teardown, :loop_count) do
    # @param [String] result - A file to write result
    def render(results:)
      prelude = preludes.reject(&:nil?).reject(&:empty?).join("\n")
      ERB.new(<<-RUBY).result_with_hash(results: results)
Warning[:experimental] = false
# shareable-constant-value: experimental_everything
#{prelude}

if #{loop_count} == 1
  __bmdv_loop_before = 0
  __bmdv_loop_after = 0
else
  __bmdv_loop_before = Time.new
  #{while_loop('', loop_count, id: 0)}
  __bmdv_loop_after = Time.new
end

__bmdv_ractors = []
<% results.size.times do %>
__bmdv_ractors << Ractor.new(__bmdv_loop_after - __bmdv_loop_before) { |__bmdv_loop_time|
  __bmdv_time = Time
  __bmdv_script_before = __bmdv_time.new
  #{while_loop(script, loop_count, id: 1)}
  __bmdv_script_after = __bmdv_time.new

  (__bmdv_script_after - __bmdv_script_before) - __bmdv_loop_time
}
<% end %>

# Wait for all Ractors before executing code to write results
__bmdv_ractors.map!(&:value)

<% results.each do |result| %>
File.write(<%= result.dump %>, __bmdv_ractors.shift)
<% end %>

#{teardown}
      RUBY
    end

    private

    # id is to prevent:
    # can not isolate a Proc because it accesses outer variables (__bmdv_i)
    def while_loop(content, times, id:)
      if !times.is_a?(Integer) || times <= 0
        raise ArgumentError.new("Unexpected times: #{times.inspect}")
      elsif times == 1
        return content
      end

      # TODO: execute in batch
      <<-RUBY
__bmdv_i#{id} = 0
while __bmdv_i#{id} < #{times}
  #{content}
  __bmdv_i#{id} += 1
end
      RUBY
    end
  end
  private_constant :BenchmarkScript
end
