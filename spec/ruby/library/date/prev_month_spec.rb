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
end
