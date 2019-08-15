require_relative '../../spec_helper'
require 'date'

describe "Date#prev_day" do
  it "returns previous day" do
    d = Date.new(2000, 7, 2).prev_day
    d.should == Date.new(2000, 7, 1)
  end

  it "returns three days ago across months" do
    d = Date.new(2000, 7, 2).prev_day(3)
    d.should == Date.new(2000, 6, 29)
  end
end
