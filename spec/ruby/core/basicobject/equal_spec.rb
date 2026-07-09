require_relative '../../spec_helper'

describe "BasicObject#equal?" do
  it "is an alias of BasicObject#==" do
    BasicObject.instance_method(:equal?).should == BasicObject.instance_method(:==)
  end
end
