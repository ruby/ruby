require_relative '../../spec_helper'
require 'date'

describe "DateTime.commercial" do
  it "needs to be reviewed for spec completeness"

  it "preserves fractional seconds" do
    DateTime.commercial(2009, 18, 4, 15, 57, Rational(3, 2)).sec_fraction.should == Rational(1, 2)
  end
end
