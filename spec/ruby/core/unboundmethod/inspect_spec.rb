require_relative '../../spec_helper'

describe "UnboundMethod#inspect" do
  it "is an alias of UnboundMethod#to_s" do
    UnboundMethod.instance_method(:inspect).should == UnboundMethod.instance_method(:to_s)
  end
end
