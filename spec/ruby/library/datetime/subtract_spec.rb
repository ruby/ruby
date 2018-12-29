require_relative '../../spec_helper'
require 'date'

describe "DateTime#-" do
  it "is able to subtract sub-millisecond precision values" do
    date = DateTime.new(2017)
    diff = Rational(123456789, 24*60*60*1000*1000)
    ((date + diff) - date).should == diff
    (date - (date + diff)).should == -diff
    (date - (date - diff)).should == diff
    ((date - diff) - date).should == -diff
  end

  it "correctly calculates sub-millisecond time differences" do  #5493
    dt1 = DateTime.new(2018, 1, 1, 0, 0, 30)
    dt2 = DateTime.new(2018, 1, 1, 0, 1, 29.000001)
    ((dt2 - dt1) * 24 * 60 * 60).should == 59.000001
  end
end
