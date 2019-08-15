require_relative '../../spec_helper'
require 'date'

describe "DateTime#to_date" do
  it "returns an instance of Date" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_date.should be_kind_of(Date)
  end

  it "maintains the same year" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_date.year.should == dt.year
  end

  it "maintains the same month" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_date.mon.should == dt.mon
  end

  it "maintains the same day" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_date.day.should == dt.day
  end

  it "maintains the same mday" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_date.mday.should == dt.mday
  end

  it "maintains the same julian day regardless of local time or zone" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')

    with_timezone("Pacific/Pago_Pago", -11) do
      dt.to_date.jd.should == dt.jd
    end
  end
end
