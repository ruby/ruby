require_relative '../../spec_helper'

describe "Symbol#size" do
  it "is an alias of Symbol#length" do
    Symbol.instance_method(:size).should == Symbol.instance_method(:length)
  end
end
