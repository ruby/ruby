require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#argv" do
  before :each do
    ScratchPad.clear

    @saved_argv = ARGV.dup
    @argv = ["a", "b"]
  end

  it "replaces and restores the value of ARGV" do
    argv @argv
    expect(ARGV).to eq(@argv)
    argv :restore
    expect(ARGV).to eq(@saved_argv)
  end

  it "yields to the block after setting ARGV" do
    argv @argv do
      ScratchPad.record ARGV.dup
    end
    expect(ScratchPad.recorded).to eq(@argv)
    expect(ARGV).to eq(@saved_argv)
  end
end
