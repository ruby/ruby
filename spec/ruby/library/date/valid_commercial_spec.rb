require_relative '../../spec_helper'
require 'date'

describe "Date.valid_commercial?" do
  it "returns true if it is a valid commercial date" do
    # October 1582 (the Gregorian calendar, Commercial Date)
    #      M Tu  W Th  F Sa Su
    # 39:  1  2  3  4  5  6  7
    # 40:  1  2  3  4  5  6  7
    # 41:  1  2  3  4  5  6  7
    Date.valid_commercial?(1582, 39, 4).should == true
    Date.valid_commercial?(1582, 39, 5).should == true
    Date.valid_commercial?(1582, 41, 4).should == true
    Date.valid_commercial?(1582, 41, 5).should == true
    Date.valid_commercial?(1582, 41, 4, Date::ENGLAND).should == true
    Date.valid_commercial?(1752, 37, 4, Date::ENGLAND).should == true
  end

  it "returns false it is not a valid commercial date" do
    Date.valid_commercial?(1999, 53, 1).should == false
  end

  it "handles negative week and day numbers" do
    # October 1582 (the Gregorian calendar, Commercial Date)
    #       M Tu  W Th  F Sa Su
    # -12: -7 -6 -5 -4 -3 -2 -1
    # -11: -7 -6 -5 -4 -3 -2 -1
    # -10: -7 -6 -5 -4 -3 -2 -1
    Date.valid_commercial?(1582, -12, -4).should == true
    Date.valid_commercial?(1582, -12, -3).should == true
    Date.valid_commercial?(2007, -44, -2).should == true
    Date.valid_commercial?(2008, -44, -2).should == true
    Date.valid_commercial?(1999, -53, -1).should == false
  end
end
