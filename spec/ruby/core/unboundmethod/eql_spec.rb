require_relative '../../spec_helper'

describe "UnboundMethod#eql?" do
  it "is an alias of UnboundMethod#==" do
    UnboundMethod.instance_method(:eql?).should == UnboundMethod.instance_method(:==)
  end
end
