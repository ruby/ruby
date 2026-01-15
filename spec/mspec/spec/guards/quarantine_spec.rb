require 'spec_helper'
require 'mspec/guards'

RSpec.describe QuarantineGuard, "#match?" do
  it "returns true" do
    expect(QuarantineGuard.new.match?).to eq(true)
  end
end

RSpec.describe Object, "#quarantine!" do
  before :each do
    ScratchPad.clear

    @guard = QuarantineGuard.new
    allow(QuarantineGuard).to receive(:new).and_return(@guard)
  end

  it "does not yield" do
    quarantine! { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "sets the name of the guard to :quarantine!" do
    quarantine! { }
    expect(@guard.name).to eq(:quarantine!)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(false)
    expect(@guard).to receive(:unregister)
    expect do
      quarantine! { raise Exception }
    end.to raise_error(Exception)
  end
end
