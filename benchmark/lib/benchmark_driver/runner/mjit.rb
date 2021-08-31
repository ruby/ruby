require 'benchmark_driver/struct'
require 'benchmark_driver/metric'
require 'erb'

# A runner to measure after-JIT performance easily
class BenchmarkDriver::Runner::Mjit < BenchmarkDriver::Runner::Ips
  # JobParser returns this, `BenchmarkDriver::Runner.runner_for` searches "*::Job"
  Job = Class.new(BenchmarkDriver::DefaultJob)

  # Dynamically fetched and used by `BenchmarkDriver::JobParser.parse`
  JobParser = BenchmarkDriver::DefaultJobParser.for(klass: Job, metrics: [METRIC]).extend(Module.new{
    def parse(**)
      jobs = super
      jobs.map do |job|
        job = job.dup
        job.prelude = "#{job.prelude}\n#{<<~EOS}"
          if defined?(RubyVM::JIT) && RubyVM::JIT.enabled?
            __bmdv_ruby_i = 0
            while __bmdv_ruby_i < 10000 # jit_min_calls
              #{job.script}
              __bmdv_ruby_i += 1
            end
            RubyVM::JIT.pause # compile
            #{job.script}
            RubyVM::JIT.resume; RubyVM::JIT.pause # recompile
            #{job.script}
            RubyVM::JIT.resume; RubyVM::JIT.pause # recompile 2
          end
        EOS
        job
      end
    end
  })
end
