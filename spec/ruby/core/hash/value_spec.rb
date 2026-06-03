require_relative '../../spec_helper'

describe "Hash#value?" do
  it "is an alias of Hash#has_value?" do
    Hash.instance_method(:value?).should == Hash.instance_method(:has_value?)
  end
end
