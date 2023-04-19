require_relative '../../spec_helper'

describe "Process.times" do
  it "returns a Process::Tms" do
    Process.times.should be_kind_of(Process::Tms)
  end

  # TODO: Intel C Compiler does not work this example
  # http://rubyci.s3.amazonaws.com/icc-x64/ruby-master/log/20221013T030005Z.fail.html.gz
  unless RbConfig::CONFIG['CC']&.include?("icx")
    it "returns current cpu times" do
      t = Process.times
      user = t.utime

      1 until Process.times.utime > user
      Process.times.utime.should > user
    end
  end

  guard -> do
    Process.clock_gettime(:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID)
  rescue Errno::EINVAL
    false
  end do
    it "uses getrusage when available to improve precision beyond milliseconds" do
      max = 10_000

      found = (max * 100).times.find do
        time = Process.times.utime
        !('%.6f' % time).end_with?('000')
      end

      found.should_not == nil
    end
  end
end
