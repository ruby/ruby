require_relative '../../spec_helper'

describe "Integer#magnitude" do
  it "is an alias of Integer#abs" do
    Integer.instance_method(:magnitude).should == Integer.instance_method(:abs)
  end
end
