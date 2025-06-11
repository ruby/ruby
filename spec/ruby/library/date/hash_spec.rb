require_relative '../../spec_helper'
require 'date'

describe "Date#hash" do
  it "returns the same value for equal dates" do
    Date.civil(2004, 7, 12).hash.should == Date.civil(2004, 7, 12).hash
    Date.civil(3171505571716611468830131104691, 2, 19).hash.should == Date.civil(3171505571716611468830131104691, 2, 19).hash
  end
end
