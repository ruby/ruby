require_relative '../../spec_helper'

describe "SignalException#signm" do
  it "returns the signal name" do
    -> { Process.kill(:TERM, Process.pid) }.should.raise(SignalException) { |e|
      e.signm.should == 'SIGTERM'
    }
  end
end
