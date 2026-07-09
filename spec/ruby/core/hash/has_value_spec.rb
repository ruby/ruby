require_relative '../../spec_helper'

describe "Hash#has_value?" do
  it "is an alias of Hash#value?" do
    Hash.instance_method(:has_value?).should == Hash.instance_method(:value?)
  end
end
