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
        times = 1000.times.map { Process.clock_gettime(:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID) }
        if times.count { |t| !('%.6f' % t).end_with?('000') } == 0
          skip "getrusage is not supported on this environment"
        end

        times = 1000.times.map { Process.times }
        times.count { |t| !('%.6f' % t.utime).end_with?('000') }.should > 0
        n = times.count { |t| !('%.6f' % t.stime).end_with?('000') }
        if n == 0
          # temporal debugging code for FreeBSD: https://rubyci.org/logs/rubyci.s3.amazonaws.com/freebsd11zfs/ruby-master/log/20200125T093004Z.fail.html.gz
          puts "DEBUG OUTPUT"
          p(*times)
          puts "DEBUG OUTPUT END"
        end
        n.should > 0
      end
    end
  end
end
