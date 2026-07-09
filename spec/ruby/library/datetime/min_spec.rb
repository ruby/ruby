require_relative '../../spec_helper'
require 'date'

describe "DateTime#min" do
  it "is an alias of DateTime#minute" do
    DateTime.instance_method(:min).should == DateTime.instance_method(:minute)
  end
end
