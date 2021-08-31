require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#big_endian" do
  before :each do
    @guard = BigEndianGuard.new
    allow(BigEndianGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields on big-endian platforms" do
    allow(@guard).to receive(:pattern).and_return([?\001])
    big_endian { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield on little-endian platforms" do
    allow(@guard).to receive(:pattern).and_return([?\000])
    big_endian { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "sets the name of the guard to :big_endian" do
    big_endian { }
    expect(@guard.name).to eq(:big_endian)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    allow(@guard).to receive(:pattern).and_return([?\001])
    expect(@guard).to receive(:unregister)
    expect do
      big_endian { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#little_endian" do
  before :each do
    @guard = BigEndianGuard.new
    allow(BigEndianGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields on little-endian platforms" do
    allow(@guard).to receive(:pattern).and_return([?\000])
    little_endian { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield on big-endian platforms" do
    allow(@guard).to receive(:pattern).and_return([?\001])
    little_endian { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end
end
