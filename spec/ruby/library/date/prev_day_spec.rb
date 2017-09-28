require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#prev_day" do
  it "returns previous day" do
    d = Date.new(2000, 7, 2).prev_day
    d.should == Date.new(2000, 7, 1)
  end

  it "returns three days ago" do
    d = Date.new(2000, 7, 4).prev_day(3)
    d.should == Date.new(2000, 7, 1)
  end
end
