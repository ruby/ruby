require_relative '../../spec_helper'
require_relative 'shared/now'

describe "Time.now" do
  it_behaves_like :time_now, :now

  ruby_version_is '3.1' do # https://bugs.ruby-lang.org/issues/17485
    describe ":in keyword argument" do
      it "could be UTC offset as a String in '+HH:MM or '-HH:MM' format" do
        time = Time.now(in: "+05:00")

        time.utc_offset.should == 5*60*60
        time.zone.should == nil

        time = Time.now(in: "-09:00")

        time.utc_offset.should == -9*60*60
        time.zone.should == nil

        time = Time.now(in: "-09:00:01")

        time.utc_offset.should == -(9*60*60 + 1)
        time.zone.should == nil
      end

      it "could be UTC offset as a number of seconds" do
        time = Time.now(in: 5*60*60)

        time.utc_offset.should == 5*60*60
        time.zone.should == nil

        time = Time.now(in: -9*60*60)

        time.utc_offset.should == -9*60*60
        time.zone.should == nil
      end

      it "returns a Time with UTC offset specified as a single letter military timezone" do
        Time.now(in: "W").utc_offset.should == 3600 * -10
      end

      it "could be a timezone object" do
        zone = TimeSpecs::TimezoneWithName.new(name: "Asia/Colombo")
        time = Time.now(in: zone)

        time.utc_offset.should == 5*3600+30*60
        time.zone.should == zone

        zone = TimeSpecs::TimezoneWithName.new(name: "PST")
        time = Time.now(in: zone)

        time.utc_offset.should == -9*60*60
        time.zone.should == zone
      end

      it "raises ArgumentError if format is invalid" do
        -> { Time.now(in: "+09:99") }.should raise_error(ArgumentError)
        -> { Time.now(in: "ABC") }.should raise_error(ArgumentError)
      end

      it "raises ArgumentError if String argument and hours greater than 23" do
        -> { Time.now(in: "+24:00") }.should raise_error(ArgumentError, "utc_offset out of range")
        -> { Time.now(in: "+2400") }.should raise_error(ArgumentError, "utc_offset out of range")

        -> { Time.now(in: "+99:00") }.should raise_error(ArgumentError, "utc_offset out of range")
        -> { Time.now(in: "+9900") }.should raise_error(ArgumentError, "utc_offset out of range")
      end

      it "raises ArgumentError if String argument and minutes greater than 59" do
        -> { Time.now(in: "+00:60") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:60')
        -> { Time.now(in: "+0060") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +0060')

        -> { Time.now(in: "+00:99") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:99')
        -> { Time.now(in: "+0099") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +0099')
      end

      ruby_bug '#20797', ''...'3.4' do
        it "raises ArgumentError if String argument and seconds greater than 59" do
          -> { Time.now(in: "+00:00:60") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:00:60')
          -> { Time.now(in: "+000060") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +000060')

          -> { Time.now(in: "+00:00:99") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:00:99')
          -> { Time.now(in: "+000099") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +000099')
        end
      end
    end
  end
end
