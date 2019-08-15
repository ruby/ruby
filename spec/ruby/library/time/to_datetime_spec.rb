require_relative '../../spec_helper'
require 'time'

describe "Time#to_datetime" do
  it "returns a DateTime representing the same instant" do
    time = Time.utc(3, 12, 31, 23, 58, 59)
    datetime = time.to_datetime
    datetime.year.should == 3
    datetime.month.should == 12
    datetime.day.should == 31
    datetime.hour.should == 23
    datetime.min.should == 58
    datetime.sec.should == 59
  end

  it "roundtrips" do
    time = Time.utc(3, 12, 31, 23, 58, 59)
    datetime = time.to_datetime
    datetime.to_time.utc.should == time
  end

  it "yields a DateTime with the default Calendar reform day" do
    Time.utc(1582, 10,  4, 1, 2, 3).to_datetime.start.should == Date::ITALY
    Time.utc(1582, 10, 14, 1, 2, 3).to_datetime.start.should == Date::ITALY
    Time.utc(1582, 10, 15, 1, 2, 3).to_datetime.start.should == Date::ITALY
  end
end
