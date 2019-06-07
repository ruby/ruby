require_relative '../../spec_helper'
require_relative 'fixtures/clocks'

describe "Process.clock_getres" do
  # clock_getres() seems completely buggy on FreeBSD:
  # https://rubyci.org/logs/rubyci.s3.amazonaws.com/freebsd11zfs/ruby-trunk/log/20190428T093003Z.fail.html.gz
  platform_is_not :freebsd, :openbsd do
    # NOTE: Look at fixtures/clocks.rb for clock and OS-specific exclusions
    ProcessSpecs.clock_constants_for_resolution_checks.each do |name, value|
      it "matches the clock in practice for Process::#{name}" do
        times = []
        10_000.times do
          times << Process.clock_gettime(value, :nanosecond)
        end
        reported = Process.clock_getres(value, :nanosecond)

        # The clock should not be more accurate than reported (times should be
        # a multiple of reported precision.)
        times.select { |t| t % reported > 0 }.should be_empty

        # We're assuming precision is a multiple of ten - it may or may not
        # be an incompatibility if it isn't but we'd like to notice this,
        # and the spec following these wouldn't work if it isn't.
        reported.should > 0
        (reported == 1 || reported % 10 == 0).should be_true

        # The clock should not be less accurate than reported (times should
        # not all be a multiple of the next precision up, assuming precisions
        # are multiples of ten.)
        times.select { |t| t % (reported * 10) == 0 }.size.should_not == times.size
      end
    end
  end

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

  platform_is_not :solaris, :aix, :openbsd do
    it "with Process::CLOCK_REALTIME reports at least 1 microsecond" do
      Process.clock_getres(Process::CLOCK_REALTIME, :nanosecond).should <= 1_000
    end
  end

  platform_is_not :aix, :openbsd do
    it "with Process::CLOCK_MONOTONIC reports at least 1 microsecond" do
      Process.clock_getres(Process::CLOCK_MONOTONIC, :nanosecond).should <= 1_000
    end
  end
end
