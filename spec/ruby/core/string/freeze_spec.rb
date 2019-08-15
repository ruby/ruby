require_relative '../../spec_helper'

describe "String#freeze" do

  it "produces the same object whenever called on an instance of a literal in the source" do
    "abc".freeze.should equal "abc".freeze
  end

  it "doesn't produce the same object for different instances of literals in the source" do
    "abc".should_not equal "abc"
  end

  it "being a special form doesn't change the value of defined?" do
    defined?("abc".freeze).should == "method"
  end

end
