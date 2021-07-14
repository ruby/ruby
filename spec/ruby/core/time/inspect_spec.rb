require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Time#inspect" do
  it_behaves_like :inspect, :inspect

  ruby_version_is "2.7" do
    it "preserves microseconds" do
      t = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
      t.inspect.should == "2007-11-01 15:25:00.123456 UTC"
    end

    it "omits trailing zeros from microseconds" do
      t = Time.utc(2007, 11, 1, 15, 25, 0, 100000)
      t.inspect.should == "2007-11-01 15:25:00.1 UTC"
    end

    it "uses the correct time zone without microseconds" do
      t = Time.utc(2000, 1, 1)
      t = t.localtime(9*3600)
      t.inspect.should == "2000-01-01 09:00:00 +0900"
    end

    it "uses the correct time zone with microseconds" do
      t = Time.utc(2000, 1, 1, 0, 0, 0, 123456)
      t = t.localtime(9*3600)
      t.inspect.should == "2000-01-01 09:00:00.123456 +0900"
    end

    it "preserves nanoseconds" do
      t = Time.utc(2007, 11, 1, 15, 25, 0, 123456.789r)
      t.inspect.should == "2007-11-01 15:25:00.123456789 UTC"
    end
  end
end
