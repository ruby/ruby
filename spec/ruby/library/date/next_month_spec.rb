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
end
