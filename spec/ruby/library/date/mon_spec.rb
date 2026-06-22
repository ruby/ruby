require_relative '../../spec_helper'
require 'date'

describe "Date#mon" do
  it "is an alias of Date#month" do
    Date.instance_method(:mon).should == Date.instance_method(:month)
  end
end
