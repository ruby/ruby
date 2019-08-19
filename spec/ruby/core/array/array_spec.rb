require_relative '../../spec_helper'

describe "Array" do
  it "includes Enumerable" do
    Array.include?(Enumerable).should == true
  end
end
