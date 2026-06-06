require_relative '../../spec_helper'

describe "Enumerable#detect" do
  it "is an alias of Enumerable#find" do
    Enumerable.instance_method(:detect).should == Enumerable.instance_method(:find)
  end
end
