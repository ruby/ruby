require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#as_superuser" do
  before :each do
    @guard = SuperUserGuard.new
    allow(SuperUserGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when Process.euid is not 0" do
    allow(Process).to receive(:euid).and_return(501)
    as_superuser { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "yields when Process.euid is 0" do
    allow(Process).to receive(:euid).and_return(0)
    as_superuser { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "sets the name of the guard to :as_superuser" do
    as_superuser { }
    expect(@guard.name).to eq(:as_superuser)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(true)
    expect(@guard).to receive(:unregister)
    expect do
      as_superuser { raise Exception }
    end.to raise_error(Exception)
  end
end
