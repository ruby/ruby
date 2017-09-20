require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#next_day" do
  it "returns the next day" do
    d = Date.new(2000, 1, 5)
    d1 = Date.new(2000, 1, 4).next_day
    d1.should == d
  end
end
