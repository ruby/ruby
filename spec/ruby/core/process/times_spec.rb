require_relative '../../spec_helper'

describe "Process.times" do
  it "returns a Process::Tms" do
    Process.times.should.is_a?(Process::Tms)
  end

  it "returns current cpu times" do
    t = Process.times
    user = t.utime

    1 until Process.times.utime > user
    Process.times.utime.should > user
  end
end
