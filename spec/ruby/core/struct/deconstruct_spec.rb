require_relative '../../spec_helper'

describe "Struct#deconstruct" do
  it "returns an array of attribute values" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct.should == [1, 2]
  end
end
