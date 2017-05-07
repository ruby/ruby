require 'spec_helper'
require 'mspec/guards'

describe Object, "#as_user" do
  before :each do
    ScratchPad.clear
  end

  it "yields when the Process.euid is not 0" do
    Process.stub(:euid).and_return(501)
    as_user { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "does not yield when the Process.euid is 0" do
    Process.stub(:euid).and_return(0)
    as_user { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end
end
