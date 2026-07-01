require_relative '../../spec_helper'

describe "FalseClass#^" do
  it "is an alias of FalseClass#|" do
    false.method(:^).should == false.method(:|)
  end
end
