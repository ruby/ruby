require_relative '../../spec_helper'

describe "String#intern" do
  it "is an alias of String#to_sym" do
    String.instance_method(:intern).should == String.instance_method(:to_sym)
  end
end
