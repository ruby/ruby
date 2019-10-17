require_relative '../../spec_helper'

describe "GC.disable" do
  after :each do
    GC.enable
  end

  it "returns true iff the garbage collection was previously disabled" do
    GC.enable
    GC.disable.should == false
    GC.disable.should == true
    GC.disable.should == true
    GC.enable
    GC.disable.should == false
    GC.disable.should == true
  end

end
