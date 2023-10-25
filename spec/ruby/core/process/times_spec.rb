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
end
