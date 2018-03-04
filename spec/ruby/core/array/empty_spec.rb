require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#empty?" do
  it "returns true if the array has no elements" do
    [].empty?.should == true
    [1].empty?.should == false
    [1, 2].empty?.should == false
  end
end
