require_relative '../../spec_helper'

describe "GC.start" do
  it "always returns nil" do
    GC.start.should == nil
    GC.start.should == nil
  end
end
