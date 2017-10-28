require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#next_month" do
  it "returns the next month" do
    d = Date.new(2000, 7, 1).next_month
    d.should == Date.new(2000, 8, 1)
  end

  it "returns three months later" do
    d = Date.new(2000, 7, 1).next_month(3)
    d.should == Date.new(2000, 10, 1)
  end

  it "returns three months later across years" do
    d = Date.new(2000, 12, 1).next_month(3)
    d.should == Date.new(2001, 3, 1)
  end

  it "returns last day of month two months later" do
    d = Date.new(2000, 1, 31).next_month(2)
    d.should == Date.new(2000, 3, 31)
  end

  it "returns last day of next month when same day does not exist" do
    d = Date.new(2001, 1, 30).next_month
    d.should == Date.new(2001, 2, 28)
  end
end
