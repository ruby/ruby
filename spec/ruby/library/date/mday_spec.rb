require_relative '../../spec_helper'
require 'date'

describe "Date#mday" do
  it "is an alias of Date#day" do
    Date.instance_method(:mday).should == Date.instance_method(:day)
  end
end
