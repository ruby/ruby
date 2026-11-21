require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#each_pair" do
  it "is an alias of ObjectSpace::WeakMap#each" do
    ObjectSpace::WeakMap.instance_method(:each_pair).should ==
      ObjectSpace::WeakMap.instance_method(:each)
  end
end
