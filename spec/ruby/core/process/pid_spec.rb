require_relative '../../spec_helper'

describe "Process.pid" do
  it "returns the process id of this process" do
    pid = Process.pid
    pid.should.is_a?(Integer)
    Process.pid.should == pid
  end
end
