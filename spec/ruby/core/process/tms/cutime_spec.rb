require_relative '../../../spec_helper'

describe "Process::Tms#cutime" do
  it "returns cutime attribute" do
    cutime = Object.new
    Process::Tms.new(nil, nil, cutime, nil).cutime.should == cutime
  end
end

describe "Process::Tms#cutime=" do
  it "assigns a value to the cutime attribute" do
    cutime = Object.new
    tms = Process::Tms.new
    tms.cutime = cutime
    tms.cutime.should == cutime
  end
end
