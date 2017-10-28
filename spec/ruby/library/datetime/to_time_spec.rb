require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "DateTime#to_time" do
  it "yields a new Time object" do
    DateTime.now.to_time.should be_kind_of(Time)
  end

  ruby_version_is "2.4" do
    it "preserves the same time regardless of local time or zone" do
      date = DateTime.new(2012, 12, 24, 12, 23, 00, '+03:00')

      with_timezone("Pactific/Pago_Pago", -11) do
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
end
