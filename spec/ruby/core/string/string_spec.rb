require_relative '../../spec_helper'

describe "String" do
  it "includes Comparable" do
    String.include?(Comparable).should == true
  end
end
