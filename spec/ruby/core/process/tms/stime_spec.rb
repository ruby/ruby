require_relative '../../../spec_helper'

describe "Process::Tms#stime" do
  it "returns stime attribute" do
    stime = Object.new
    Process::Tms.new(nil, stime, nil, nil).stime.should == stime
  end
end

describe "Process::Tms#stime=" do
  it "assigns a value to the stime attribute" do
    stime = Object.new
    tms = Process::Tms.new
    tms.stime = stime
    tms.stime.should == stime
  end
end
