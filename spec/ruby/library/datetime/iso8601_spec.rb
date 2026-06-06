require_relative '../../spec_helper'
require 'date'

describe "DateTime.iso8601" do
  it "needs to be reviewed for spec completeness"
end

describe "DateTime#iso8601" do
  it "is an alias of DateTime#isoxmlschema8601" do
    DateTime.instance_method(:iso8601).should == DateTime.instance_method(:xmlschema)
  end
end
