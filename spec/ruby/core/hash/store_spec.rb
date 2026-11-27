require_relative '../../spec_helper'

describe "Hash#store" do
  it "is an alias of Hash#[]=" do
    Hash.instance_method(:store).should == Hash.instance_method(:[]=)
  end
end
