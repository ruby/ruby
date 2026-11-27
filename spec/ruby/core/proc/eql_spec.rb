require_relative '../../spec_helper'

describe "Proc#eql?" do
  it "is an alias of Proc#==" do
    Proc.instance_method(:eql?).should == Proc.instance_method(:==)
  end
end
