require_relative '../../spec_helper'

describe "Enumerable#reduce" do
  it "is an alias of Enumerable#inject" do
    Enumerable.instance_method(:reduce).should == Enumerable.instance_method(:inject)
  end
end
