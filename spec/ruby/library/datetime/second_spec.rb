require_relative '../../spec_helper'
require 'date'

describe "DateTime#second" do
  it "returns 0 seconds if passed no arguments" do
    d = DateTime.new
    d.second.should == 0
  end

  it "returns the seconds passed in the arguments" do
    new_datetime(second: 5).second.should == 5
  end

  it "adds 60 to negative values" do
    new_datetime(second: -20).second.should == 40
  end

  it "returns the absolute value of a Rational" do
    new_datetime(second: 5 + Rational(1,2)).second.should == 5
  end

  it "returns the absolute value of a float" do
    new_datetime(second: 5.5).second.should == 5
  end

  it "raises an error when minute is given as a rational" do
    -> { new_datetime(minute: 5 + Rational(1,2)) }.should.raise(ArgumentError)
  end

  it "raises an error, when the second is smaller than -60" do
    -> { new_datetime(second: -61) }.should.raise(ArgumentError)
  end

  it "raises an error, when the second is greater or equal than 60" do
    -> { new_datetime(second: 60) }.should.raise(ArgumentError)
  end

  it "raises an error for second fractions smaller than -60" do
    -> { new_datetime(second: -60 - Rational(1,2))}.should.raise(ArgumentError)
  end

  it "takes a second fraction near 60" do
    new_datetime(second: 59 + Rational(1,2)).second.should == 59
  end
end
