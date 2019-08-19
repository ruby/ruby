require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#new_datetime" do
  it "returns a default DateTime instance" do
    new_datetime.should == DateTime.new
  end

  it "returns a DateTime instance with the specified year value" do
    d = new_datetime :year => 1970
    d.year.should == 1970
  end

  it "returns a DateTime instance with the specified month value" do
    d = new_datetime :month => 11
    d.mon.should == 11
  end

  it "returns a DateTime instance with the specified day value" do
    d = new_datetime :day => 23
    d.day.should == 23
  end

  it "returns a DateTime instance with the specified hour value" do
    d = new_datetime :hour => 10
    d.hour.should == 10
  end

  it "returns a DateTime instance with the specified minute value" do
    d = new_datetime :minute => 10
    d.min.should == 10
  end

  it "returns a DateTime instance with the specified second value" do
    d = new_datetime :second => 2
    d.sec.should == 2
  end

  it "returns a DateTime instance with the specified offset value" do
    d = new_datetime :offset => Rational(3,24)
    d.offset.should == Rational(3,24)
  end
end
