require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#next_day" do
  it "returns the next day" do
    d = Date.new(2000, 1, 4).next_day
    d.should == Date.new(2000, 1, 5)
  end

  it "returns three days later across months" do
    d = Date.new(2000, 1, 30).next_day(3)
    d.should == Date.new(2000, 2, 2)
  end
end
