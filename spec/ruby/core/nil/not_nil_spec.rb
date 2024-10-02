require_relative '../../spec_helper'

describe "NilClass#not_nil!" do
  it "raises a TypeError" do
    -> { nil.not_nil! }.should raise_error(TypeError, "Called `not_nil!` on nil")
  end
end

describe "NilClass#not_nil" do
  it "returns the value of the block" do
    nil.not_nil { 42 }.should == 42
  end
end
