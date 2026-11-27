require_relative '../../spec_helper'
require 'date'

describe "DateTime#second_fraction" do
  it "is an alias of DateTime#sec_fraction" do
    DateTime.instance_method(:second_fraction).should == DateTime.instance_method(:sec_fraction)
  end
end
