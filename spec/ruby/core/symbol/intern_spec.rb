require_relative '../../spec_helper'

describe "Symbol#intern" do
  it "is an alias of Symbol#to_sym" do
    Symbol.instance_method(:intern).should == Symbol.instance_method(:to_sym)
  end
end
