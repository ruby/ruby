require_relative '../../spec_helper'
require 'date'

describe "Date#succ" do
  it "is an alias of Date#next" do
    Date.instance_method(:succ).should == Date.instance_method(:next)
  end
end
