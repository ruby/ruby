require_relative '../../spec_helper'
require 'date'

describe "Date#month" do
  it "returns the month" do
    m = Date.new(2000, 7, 1).month
    m.should == 7
  end
end
