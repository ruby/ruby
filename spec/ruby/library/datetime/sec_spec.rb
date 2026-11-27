require_relative '../../spec_helper'
require 'date'

describe "DateTime#sec" do
  it "is an alias of DateTime#second" do
    DateTime.instance_method(:sec).should == DateTime.instance_method(:second)
  end
end
