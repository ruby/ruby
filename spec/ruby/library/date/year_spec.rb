require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#year" do
  it "returns the year" do
    y = Date.new(2000, 7, 1).year
    y.should == 2000
  end
end
