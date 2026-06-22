require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct#inspect" do
  it "is an alias of OpenStruct#to_s" do
    OpenStruct.instance_method(:inspect).should == OpenStruct.instance_method(:to_s)
  end
end
