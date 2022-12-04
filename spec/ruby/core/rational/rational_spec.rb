require_relative '../../spec_helper'

describe "Rational" do
  it "includes Comparable" do
    Rational.include?(Comparable).should == true
  end

  it "does not respond to new" do
    -> { Rational.new(1) }.should raise_error(NoMethodError)
  end
end
