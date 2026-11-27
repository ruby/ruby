require_relative '../../spec_helper'

describe "Hash#length" do
  it "is an alias of Hash#size" do
    Hash.instance_method(:size).should == Hash.instance_method(:length)
  end
end
