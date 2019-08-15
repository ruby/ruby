require_relative '../../spec_helper'
require 'date'

describe "Date#day" do
  it "returns the day" do
    d = Date.new(2000, 7, 1).day
    d.should == 1
  end
end
