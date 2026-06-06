require_relative '../../spec_helper'

describe "Symbol#id2name" do
  it "is an alias of Symbol#to_s" do
    Symbol.instance_method(:id2name).should == Symbol.instance_method(:to_s)
  end
end
