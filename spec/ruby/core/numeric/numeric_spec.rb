require_relative '../../spec_helper'

describe "Numeric" do
  it "includes Comparable" do
    Numeric.include?(Comparable).should == true
  end
end
