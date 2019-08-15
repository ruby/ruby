require_relative '../../spec_helper'

describe "Range" do
  it "includes Enumerable" do
    Range.include?(Enumerable).should == true
  end
end
