require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#with_block_device" do
  before :each do
    ScratchPad.clear

    @guard = BlockDeviceGuard.new
    allow(BlockDeviceGuard).to receive(:new).and_return(@guard)
  end

  platform_is_not :freebsd, :windows do
    it "yields if block device is available" do
      expect(@guard).to receive(:`).and_return("block devices")
      with_block_device { ScratchPad.record :yield }
      expect(ScratchPad.recorded).to eq(:yield)
    end

    it "does not yield if block device is not available" do
      expect(@guard).to receive(:`).and_return(nil)
      with_block_device { ScratchPad.record :yield }
      expect(ScratchPad.recorded).not_to eq(:yield)
    end
  end

  platform_is :freebsd, :windows do
    it "does not yield, since platform does not support block devices" do
      expect(@guard).not_to receive(:`)
      with_block_device { ScratchPad.record :yield }
      expect(ScratchPad.recorded).not_to eq(:yield)
    end
  end

  it "sets the name of the guard to :with_block_device" do
    with_block_device { }
    expect(@guard.name).to eq(:with_block_device)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(true)
    expect(@guard).to receive(:unregister)
    expect do
      with_block_device { raise Exception }
    end.to raise_error(Exception)
  end
end
