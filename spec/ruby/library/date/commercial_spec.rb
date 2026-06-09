require 'date'
require_relative '../../spec_helper'

# reference:
# October 1582 (the Gregorian calendar, Civil Date)
#   S   M  Tu   W  Th   F   S
#       1   2   3   4  15  16
#  17  18  19  20  21  22  23
#  24  25  26  27  28  29  30
#  31
describe "Date.commercial" do
  it "creates a Date for Julian Day Number day 0 by default" do
    d = Date.commercial
    d.year.should == -4712
    d.month.should == 1
    d.day.should == 1
  end

  it "creates a Date for the monday in the year and week given" do
    d = Date.commercial(2000, 1)
    d.year.should == 2000
    d.month.should == 1
    d.day.should == 3
    d.cwday.should == 1
  end

  it "creates a Date for the correct day given the year, week and day number" do
    d = Date.commercial(2004, 1, 1)
    d.year.should == 2003
    d.month.should == 12
    d.day.should == 29
    d.cwday.should == 1
    d.cweek.should == 1
    d.cwyear.should == 2004
  end

  it "creates only Date objects for valid weeks" do
    -> { Date.commercial(2004, 53, 1) }.should_not.raise(ArgumentError)
    -> { Date.commercial(2004, 53, 0) }.should.raise(ArgumentError)
    -> { Date.commercial(2004, 53, 8) }.should.raise(ArgumentError)
    -> { Date.commercial(2004, 54, 1) }.should.raise(ArgumentError)
    -> { Date.commercial(2004,  0, 1) }.should.raise(ArgumentError)

    -> { Date.commercial(2003, 52, 1) }.should_not.raise(ArgumentError)
    -> { Date.commercial(2003, 53, 1) }.should.raise(ArgumentError)
    -> { Date.commercial(2003, 52, 0) }.should.raise(ArgumentError)
    -> { Date.commercial(2003, 52, 8) }.should.raise(ArgumentError)
  end
end
