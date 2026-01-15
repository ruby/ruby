require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe ScratchPad do
  it "records an object and returns a previously recorded object" do
    ScratchPad.record :this
    expect(ScratchPad.recorded).to eq(:this)
  end

  it "clears the recorded object" do
    ScratchPad.record :that
    expect(ScratchPad.recorded).to eq(:that)
    ScratchPad.clear
    expect(ScratchPad.recorded).to eq(nil)
  end

  it "provides a convenience shortcut to append to a previously recorded object" do
    ScratchPad.record []
    ScratchPad << :new
    ScratchPad << :another
    expect(ScratchPad.recorded).to eq([:new, :another])
  end
end
