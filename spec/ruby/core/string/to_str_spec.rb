require_relative '../../spec_helper'

describe "String#to_str" do
  it "is an alias of String#to_s" do
    String.instance_method(:to_str).should == String.instance_method(:to_s)
  end
end
