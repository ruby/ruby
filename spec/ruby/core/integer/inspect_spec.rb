require_relative '../../spec_helper'

describe "Integer#inspect" do
  it "is an alias of Integer#to_s" do
    Integer.instance_method(:inspect).should == Integer.instance_method(:to_s)
  end
end
