require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#prev_month" do
  it "returns previous month" do
    d = Date.new(2000, 9, 1).prev_month
    d.should == Date.new(2000, 8, 1)
  end

  it "returns three months ago" do
    d = Date.new(2000, 10, 1).prev_month(3)
    d.should == Date.new(2000, 7, 1)
  end

  it "returns three months ago across years" do
    d = Date.new(2000, 1, 1).prev_month(3)
    d.should == Date.new(1999, 10, 1)
  end

  it "returns last day of month two months ago" do
    d = Date.new(2000, 3, 31).prev_month(2)
    d.should == Date.new(2000, 1, 31)
  end

  it "returns last day of previous month when same day does not exist" do
    d = Date.new(2001, 3, 30).prev_month
    d.should == Date.new(2001, 2, 28)
  end
end
