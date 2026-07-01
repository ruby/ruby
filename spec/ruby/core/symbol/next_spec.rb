require_relative '../../spec_helper'

describe "Symbol#next" do
  it "is an alias of Symbol#succ" do
    Symbol.instance_method(:next).should == Symbol.instance_method(:succ)
  end
end
