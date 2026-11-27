require_relative '../../spec_helper'

describe "Hash#filter" do
  it "is an alias of Hash#select" do
    Hash.instance_method(:filter).should == Hash.instance_method(:select)
  end
end

describe "Hash#filter!" do
  it "is an alias of Hash#select!" do
    Hash.instance_method(:filter!).should == Hash.instance_method(:select!)
  end
end
