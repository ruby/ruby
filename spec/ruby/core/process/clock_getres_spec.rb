require_relative '../../spec_helper'

describe "Process.clock_getres" do
  # These are documented

  it "with :GETTIMEOFDAY_BASED_CLOCK_REALTIME reports 1 microsecond" do
    Process.clock_getres(:GETTIMEOFDAY_BASED_CLOCK_REALTIME, :nanosecond).should == 1_000
  end

  it "with :TIME_BASED_CLOCK_REALTIME reports 1 second" do
    Process.clock_getres(:TIME_BASED_CLOCK_REALTIME, :nanosecond).should == 1_000_000_000
  end

  platform_is_not :windows do
    it "with :GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID reports 1 microsecond" do
      Process.clock_getres(:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID, :nanosecond).should == 1_000
    end
  end

  # These are observed

  platform_is :linux, :darwin, :windows do
    it "with Process::CLOCK_REALTIME reports at least 10 millisecond" do
      Process.clock_getres(Process::CLOCK_REALTIME, :nanosecond).should <= 10_000_000
    end
  end

  platform_is :linux, :darwin, :windows do
    it "with Process::CLOCK_MONOTONIC reports at least 10 millisecond" do
      Process.clock_getres(Process::CLOCK_MONOTONIC, :nanosecond).should <= 10_000_000
    end
  end
end
