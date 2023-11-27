require_relative '../../spec_helper'
require 'date'

describe "Date.iso8601" do
  it "parses YYYY-MM-DD into a Date object" do
    d = Date.iso8601("2018-01-01")
    d.should == Date.civil(2018, 1, 1)
  end

  it "parses YYYYMMDD into a Date object" do
    d = Date.iso8601("20180715")
    d.should == Date.civil(2018, 7, 15)
  end

  it "parses a negative Date" do
    d = Date.iso8601("-4712-01-01")
    d.should == Date.civil(-4712, 1, 1)
  end

  it "parses a StringSubclass into a Date object" do
    d = Date.iso8601(Class.new(String).new("-4712-01-01"))
    d.should == Date.civil(-4712, 1, 1)
  end

  it "raises a Date::Error if the argument is a invalid Date" do
    -> {
      Date.iso8601('invalid')
    }.should raise_error(Date::Error, "invalid date")
  end

  it "raises a Date::Error when passed a nil" do
    -> {
      Date.iso8601(nil)
    }.should raise_error(Date::Error, "invalid date")
  end

  it "raises a TypeError when passed an Object" do
    -> { Date.iso8601(Object.new) }.should raise_error(TypeError)
  end
end

describe "Date._iso8601" do
  it "returns an empty hash if the argument is a invalid Date" do
    h = Date._iso8601('invalid')
    h.should == {}
  end

  it "returns an empty hash if the argument is nil" do
    h = Date._iso8601(nil)
    h.should == {}
  end

  it "raises a TypeError when passed an Object" do
    -> { Date._iso8601(Object.new) }.should raise_error(TypeError)
  end
end
