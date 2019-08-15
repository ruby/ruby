require 'spec_helper'
require 'mspec/guards'

describe Object, "#as_superuser" do
  before :each do
    @guard = SuperUserGuard.new
    SuperUserGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when Process.euid is not 0" do
    Process.stub(:euid).and_return(501)
    as_superuser { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "yields when Process.euid is 0" do
    Process.stub(:euid).and_return(0)
    as_superuser { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "sets the name of the guard to :as_superuser" do
    as_superuser { }
    @guard.name.should == :as_superuser
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(true)
    @guard.should_receive(:unregister)
    lambda do
      as_superuser { raise Exception }
    end.should raise_error(Exception)
  end
end
