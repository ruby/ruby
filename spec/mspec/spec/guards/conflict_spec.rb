require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#conflicts_with" do
  before :each do
    hide_deprecation_warnings
    ScratchPad.clear
  end

  it "does not yield if Object.constants includes any of the arguments" do
    allow(Object).to receive(:constants).and_return(["SomeClass", "OtherClass"])
    conflicts_with(:SomeClass, :AClass, :BClass) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "does not yield if Object.constants (as Symbols) includes any of the arguments" do
    allow(Object).to receive(:constants).and_return([:SomeClass, :OtherClass])
    conflicts_with(:SomeClass, :AClass, :BClass) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "yields if Object.constants does not include any of the arguments" do
    allow(Object).to receive(:constants).and_return(["SomeClass", "OtherClass"])
    conflicts_with(:AClass, :BClass) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "yields if Object.constants (as Symbols) does not include any of the arguments" do
    allow(Object).to receive(:constants).and_return([:SomeClass, :OtherClass])
    conflicts_with(:AClass, :BClass) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end
end

RSpec.describe Object, "#conflicts_with" do
  before :each do
    hide_deprecation_warnings
    @guard = ConflictsGuard.new
    allow(ConflictsGuard).to receive(:new).and_return(@guard)
  end

  it "sets the name of the guard to :conflicts_with" do
    conflicts_with(:AClass, :BClass) { }
    expect(@guard.name).to eq(:conflicts_with)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:unregister)
    expect do
      conflicts_with(:AClass, :BClass) { raise Exception }
    end.to raise_error(Exception)
  end
end
