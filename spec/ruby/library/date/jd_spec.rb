require_relative '../../spec_helper'
require 'date'

describe "Date#jd" do
  it "determines the Julian day for a Date object" do
    Date.civil(2008, 1, 16).jd.should == 2454482
  end
end

describe "Date.jd" do
  it "constructs a Date object if passed a Julian day" do
    Date.jd(2454482).should == Date.civil(2008, 1, 16)
  end

  it "returns a Date object representing Julian day 0 (-4712-01-01) if no arguments passed" do
    Date.jd.should == Date.civil(-4712, 1, 1)
  end

  it "constructs a Date object if passed a negative number" do
    Date.jd(-1).should == Date.civil(-4713, 12, 31)
  end
end
