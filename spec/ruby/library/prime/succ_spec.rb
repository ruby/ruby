require_relative '../../spec_helper'
require 'prime'

describe "Prime#succ" do
  it "is an alias of Prime#next" do
    p = Prime.instance.each
    p.method(:succ).should == p.method(:next)
  end
end
