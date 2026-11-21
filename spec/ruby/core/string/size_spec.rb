require_relative '../../spec_helper'

describe "String#size" do
  it "is an alias of String#length" do
    String.instance_method(:size).should == String.instance_method(:length)
  end
end
