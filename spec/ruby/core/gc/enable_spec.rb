require_relative '../../spec_helper'

describe "GC.enable" do

  it "returns true if and only if the garbage collection was already disabled" do
    GC.enable
    GC.enable.should == false
    GC.disable
    GC.enable.should == true
    GC.enable.should == false
  end

end
