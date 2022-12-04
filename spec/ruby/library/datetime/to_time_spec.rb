require_relative '../../spec_helper'
require 'date'

describe "DateTime#to_time" do
  it "yields a new Time object" do
    DateTime.now.to_time.should be_kind_of(Time)
  end

  it "returns a Time representing the same instant" do
    datetime = DateTime.civil(2012, 12, 31, 23, 58, 59)
    time = datetime.to_time.utc

    time.year.should == 2012
    time.month.should == 12
    time.day.should == 31
    time.hour.should == 23
    time.min.should == 58
    time.sec.should == 59
  end

  date_version = defined?(Date::VERSION) ? Date::VERSION : '0.0.0'
  version_is(date_version, '3.2.3') do
    it "returns a Time representing the same instant before Gregorian" do
      datetime = DateTime.civil(1582, 10, 4, 23, 58, 59)
      time = datetime.to_time.utc
      time.year.should == 1582
      time.month.should == 10
      time.day.should == 14
      time.hour.should == 23
      time.min.should == 58
      time.sec.should == 59
    end
  end

  it "preserves the same time regardless of local time or zone" do
    date = DateTime.new(2012, 12, 24, 12, 23, 00, '+03:00')

    with_timezone("Pacific/Pago_Pago", -11) do
      time = date.to_time

      time.utc_offset.should == 3 * 3600
      time.year.should == date.year
      time.mon.should == date.mon
      time.day.should == date.day
      time.hour.should == date.hour
      time.min.should == date.min
      time.sec.should == date.sec
    end
  end
end
