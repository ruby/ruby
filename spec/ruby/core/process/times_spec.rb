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
        times = 100.times.map { Process.clock_gettime(:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID) }
        if times.count { |t| ((t * 1e6).to_i % 1000) > 0 } == 0
          skip "getrusage is not supported on this environment"
        end

        times = 100.times.map { Process.times }
        times.count { |t| ((t.utime * 1e6).to_i % 1000) > 0 }.should > 0
        times.count { |t| ((t.stime * 1e6).to_i % 1000) > 0 }.should > 0
      end
    end
  end
end
