require_relative '../../spec_helper'

describe "Struct#deconstruct" do
  it "is an alias of Struct#to_a" do
    Struct.instance_method(:deconstruct).should == Struct.instance_method(:to_a)
  end
end
