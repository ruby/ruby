require_relative '../../spec_helper'
require 'date'

describe "Date#thursday?" do
  it "should be thursday" do
    Date.new(2000, 1, 6).thursday?.should == true
  end
end
