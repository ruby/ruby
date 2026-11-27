require_relative '../../spec_helper'
require 'date'

describe "Date#gregorian_leap?" do
  it "returns true if a year is a leap year in the Gregorian calendar" do
    Date.gregorian_leap?(2000).should == true
    Date.gregorian_leap?(2004).should == true
  end

  it "returns false if a year is not a leap year in the Gregorian calendar" do
    Date.gregorian_leap?(1900).should == false
    Date.gregorian_leap?(1999).should == false
    Date.gregorian_leap?(2002).should == false
  end
end
