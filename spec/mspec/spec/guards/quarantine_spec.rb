require 'spec_helper'
require 'mspec/guards'

describe QuarantineGuard, "#match?" do
  it "returns true" do
    QuarantineGuard.new.match?.should == true
  end
end

describe Object, "#quarantine!" do
  before :each do
    ScratchPad.clear

    @guard = QuarantineGuard.new
    QuarantineGuard.stub(:new).and_return(@guard)
  end

  it "does not yield" do
    quarantine! { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "sets the name of the guard to :quarantine!" do
    quarantine! { }
    @guard.name.should == :quarantine!
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(false)
    @guard.should_receive(:unregister)
    lambda do
      quarantine! { raise Exception }
    end.should raise_error(Exception)
  end
end
