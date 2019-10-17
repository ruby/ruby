require_relative '../../spec_helper'
require 'date'

describe "Date#year" do
  it "returns the year" do
    y = Date.new(2000, 7, 1).year
    y.should == 2000
  end
end
