require_relative '../../spec_helper'

describe "Time#nsec" do
  it "returns 0 for a Time constructed with a whole number of seconds" do
    Time.at(100).nsec.should == 0
  end

  it "returns the nanoseconds part of a Time constructed with a Float number of seconds" do
    Time.at(10.75).nsec.should == 750_000_000
  end

  it "returns the nanoseconds part of a Time constructed with an Integer number of microseconds" do
    Time.at(0, 999_999).nsec.should == 999_999_000
  end

  it "returns the nanoseconds part of a Time constructed with an Float number of microseconds" do
    Time.at(0, 3.75).nsec.should == 3750
  end

  it "returns the nanoseconds part of a Time constructed with a Rational number of seconds" do
    Time.at(Rational(3, 2)).nsec.should == 500_000_000
  end

  it "returns the nanoseconds part of a Time constructed with an Rational number of microseconds" do
    Time.at(0, Rational(99, 10)).nsec.should == 9900
  end

  it "returns a positive value for dates before the epoch" do
    Time.utc(1969, 11, 12, 13, 18, 57, 404240).nsec.should == 404240000
  end
end
