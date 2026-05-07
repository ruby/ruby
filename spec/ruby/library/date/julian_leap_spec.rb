require_relative '../../spec_helper'
require 'date'

describe "Date.julian_leap?" do
  it "determines whether a year is a leap year in the Julian calendar" do
    Date.julian_leap?(1900).should == true
    Date.julian_leap?(2000).should == true
    Date.julian_leap?(2004).should == true
  end

  it "determines whether a year is not a leap year in the Julian calendar" do
    Date.julian_leap?(1999).should == false
    Date.julian_leap?(2002).should == false
  end
end
