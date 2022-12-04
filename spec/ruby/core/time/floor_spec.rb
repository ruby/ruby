require_relative '../../spec_helper'

describe "Time#floor" do
  before do
    @time = Time.utc(2010, 3, 30, 5, 43, "25.123456789".to_r)
  end

  it "defaults to flooring to 0 places" do
    @time.floor.should == Time.utc(2010, 3, 30, 5, 43, 25.to_r)
  end

  it "floors to 0 decimal places with an explicit argument" do
    @time.floor(0).should == Time.utc(2010, 3, 30, 5, 43, 25.to_r)
  end

  it "floors to 7 decimal places with an explicit argument" do
    @time.floor(7).should == Time.utc(2010, 3, 30, 5, 43, "25.1234567".to_r)
  end

  it "returns an instance of Time, even if #floor is called on a subclass" do
    subclass = Class.new(Time)
    instance = subclass.at(0)
    instance.class.should equal subclass
    instance.floor.should be_an_instance_of(Time)
  end

  it "copies own timezone to the returning value" do
    @time.zone.should == @time.floor.zone

    time = with_timezone "JST-9" do
      Time.at 0, 1
    end

    time.zone.should == time.floor.zone
  end
end
