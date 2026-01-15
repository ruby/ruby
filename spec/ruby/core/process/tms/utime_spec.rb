require_relative '../../../spec_helper'

describe "Process::Tms#utime" do
  it "returns utime attribute" do
    utime = Object.new
    Process::Tms.new(utime, nil, nil, nil).utime.should == utime
  end
end

describe "Process::Tms#utime=" do
  it "assigns a value to the ctime attribute" do
    utime = Object.new
    tms = Process::Tms.new
    tms.utime = utime
    tms.utime.should == utime
  end
end
