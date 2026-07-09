require_relative '../../spec_helper'

describe "String#next" do
  it "is an alias of String#succ" do
    String.instance_method(:next).should == String.instance_method(:succ)
  end
end

describe "String#next!" do
  it "is an alias of String#succ!" do
    String.instance_method(:next!).should == String.instance_method(:succ!)
  end
end
