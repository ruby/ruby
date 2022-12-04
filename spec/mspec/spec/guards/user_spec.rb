require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#as_user" do
  before :each do
    ScratchPad.clear
  end

  it "yields when the Process.euid is not 0" do
    allow(Process).to receive(:euid).and_return(501)
    as_user { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield when the Process.euid is 0" do
    allow(Process).to receive(:euid).and_return(0)
    as_user { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end
end
