require_relative '../../spec_helper'

describe "GC.start" do
  it "always returns nil" do
    GC.start.should == nil
    GC.start.should == nil
  end

  it "accepts keyword arguments" do
    GC.start(full_mark: true, immediate_sweep: true).should == nil
  end
end
