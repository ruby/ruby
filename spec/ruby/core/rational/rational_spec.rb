require_relative '../../spec_helper'

describe "Rational" do
  it "includes Comparable" do
    Rational.include?(Comparable).should == true
  end
end
