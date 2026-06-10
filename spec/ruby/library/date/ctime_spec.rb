require_relative '../../spec_helper'
require 'date'

describe "Date#ctime" do
  it "is an alias of Date#asctime" do
    Date.instance_method(:ctime).should == Date.instance_method(:asctime)
  end
end
