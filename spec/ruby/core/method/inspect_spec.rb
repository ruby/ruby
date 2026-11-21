require_relative '../../spec_helper'

describe "Method#inspect" do
  it "is an alias of Method#to_s" do
    Method.instance_method(:inspect).should == Method.instance_method(:to_s)
  end
end
