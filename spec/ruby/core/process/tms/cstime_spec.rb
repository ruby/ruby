require_relative '../../../spec_helper'

describe "Process::Tms#cstime" do
  it "returns cstime attribute" do
    cstime = Object.new
    Process::Tms.new(nil, nil, nil, cstime).cstime.should == cstime
  end
end

describe "Process::Tms#cstime=" do
  it "assigns a value to the cstime attribute" do
    cstime = Object.new
    tms = Process::Tms.new
    tms.cstime = cstime
    tms.cstime.should == cstime
  end
end
