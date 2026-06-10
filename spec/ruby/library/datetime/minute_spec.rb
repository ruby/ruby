require_relative '../../spec_helper'
require 'date'

describe "DateTime#minute" do
  it "returns 0 if no argument is passed" do
    DateTime.new.minute.should == 0
  end

  it "returns the minute passed as argument" do
    new_datetime(minute: 5).minute.should == 5
  end

  it "adds 60 to negative minutes" do
    new_datetime(minute: -20).minute.should == 40
  end

  it "raises an error for Rational" do
    -> { new_datetime minute: 5 + Rational(1,2) }.should.raise(ArgumentError)
  end

  it "raises an error for Float" do
    -> { new_datetime minute: 5.5 }.should.raise(ArgumentError)
  end

  it "raises an error for Rational" do
    -> { new_datetime(hour: 2 + Rational(1,2)) }.should.raise(ArgumentError)
  end

  it "raises an error, when the minute is smaller than -60" do
    -> { new_datetime(minute: -61) }.should.raise(ArgumentError)
  end

  it "raises an error, when the minute is greater or equal than 60" do
    -> { new_datetime(minute: 60) }.should.raise(ArgumentError)
  end

  it "raises an error for minute fractions smaller than -60" do
    -> { new_datetime(minute: -60 - Rational(1,2))}.should.raise(ArgumentError)
  end
end
