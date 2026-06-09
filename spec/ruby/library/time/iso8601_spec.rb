require_relative '../../spec_helper'
require 'time'

describe "Time.iso8601" do
  it "is an alias of Time.xmlschema" do
    Time.method(:iso8601).should == Time.method(:xmlschema)
  end
end
