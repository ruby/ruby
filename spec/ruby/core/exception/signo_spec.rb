require_relative '../../spec_helper'

describe "SignalException#signo" do
  it "returns the signal number" do
    -> { Process.kill(:TERM, Process.pid) }.should raise_error(SignalException) { |e|
      e.signo.should == Signal.list['TERM']
    }
  end
end
