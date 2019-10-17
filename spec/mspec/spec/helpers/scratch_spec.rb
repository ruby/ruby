require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe ScratchPad do
  it "records an object and returns a previously recorded object" do
    ScratchPad.record :this
    ScratchPad.recorded.should == :this
  end

  it "clears the recorded object" do
    ScratchPad.record :that
    ScratchPad.recorded.should == :that
    ScratchPad.clear
    ScratchPad.recorded.should == nil
  end

  it "provides a convenience shortcut to append to a previously recorded object" do
    ScratchPad.record []
    ScratchPad << :new
    ScratchPad << :another
    ScratchPad.recorded.should == [:new, :another]
  end
end
