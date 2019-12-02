require_relative '../../spec_helper'

describe "Process.times" do
  it "returns a Process::Tms" do
    Process.times.should be_kind_of(Process::Tms)
  end

  it "returns current cpu times" do
    t = Process.times
    user = t.utime

    1 until Process.times.utime > user
    Process.times.utime.should > user
  end

  ruby_version_is "2.5" do
    platform_is_not :windows do
      it "uses getrusage when available to improve precision beyond milliseconds" do
        gettimes = 100.times.map { Process.clock_gettime(:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID) }
        if gettimes.count { |t| ((t * 1e6).to_i % 1000) > 0 } == 0
          skip "getrusage is not supported on this environment"
        end

        times = 100.times.map { Process.times }

        # Creating custom matcher to show a debug message to investigate random failure
        # on Debian ci.rvm.jp like: https://gist.github.com/ko1/346983a66ba66cf288249383ca30f15a
        larger_than_0 = Class.new do
          def initialize(expected, times:, gettimes:)
            @expected = expected
            @times = times
            @gettimes = gettimes
          end

          def matches?(actual)
            @actual = actual
            @actual > @expected
          end

          def failure_message
            ["Expected #{@actual} > #{@expected}",
             "to be truthy but was false. (times: #{pp(@times)}, gettimes: #{pp(@gettimes)})"]
          end

          alias :negative_failure_message :failure_message

          private def pp(obj)
            require 'pp'
            PP.pp(obj, '')
          end
        end.new(0, times: times, gettimes: gettimes)

        times.count { |t| ((t.utime * 1e6).to_i % 1000) > 0 }.should(larger_than_0)
        times.count { |t| ((t.stime * 1e6).to_i % 1000) > 0 }.should(larger_than_0)
      end
    end
  end
end
