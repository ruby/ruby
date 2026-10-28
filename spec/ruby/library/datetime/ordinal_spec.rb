require_relative '../../spec_helper'
require 'date'

describe "DateTime.ordinal" do
  it "needs to be reviewed for spec completeness"

  it "preserves fractional seconds" do
    DateTime.ordinal(2009, 124, 15, 57, Rational(3, 2)).sec_fraction.should == Rational(1, 2)
  end
end
