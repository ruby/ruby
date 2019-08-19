require 'spec_helper'
require 'mspec/guards'

describe Object, "#conflicts_with" do
  before :each do
    hide_deprecation_warnings
    ScratchPad.clear
  end

  it "does not yield if Object.constants includes any of the arguments" do
    Object.stub(:constants).and_return(["SomeClass", "OtherClass"])
    conflicts_with(:SomeClass, :AClass, :BClass) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "does not yield if Object.constants (as Symbols) includes any of the arguments" do
    Object.stub(:constants).and_return([:SomeClass, :OtherClass])
    conflicts_with(:SomeClass, :AClass, :BClass) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "yields if Object.constants does not include any of the arguments" do
    Object.stub(:constants).and_return(["SomeClass", "OtherClass"])
    conflicts_with(:AClass, :BClass) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "yields if Object.constants (as Symbols) does not include any of the arguments" do
    Object.stub(:constants).and_return([:SomeClass, :OtherClass])
    conflicts_with(:AClass, :BClass) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end
end

describe Object, "#conflicts_with" do
  before :each do
    hide_deprecation_warnings
    @guard = ConflictsGuard.new
    ConflictsGuard.stub(:new).and_return(@guard)
  end

  it "sets the name of the guard to :conflicts_with" do
    conflicts_with(:AClass, :BClass) { }
    @guard.name.should == :conflicts_with
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:unregister)
    lambda do
      conflicts_with(:AClass, :BClass) { raise Exception }
    end.should raise_error(Exception)
  end
end
