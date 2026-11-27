require_relative '../../spec_helper'

describe "Method#eql?" do
  it "is an alias of Method#==" do
    Method.instance_method(:eql?).should == Method.instance_method(:==)
  end
end
