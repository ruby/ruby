require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#length" do
  it "is an alias of ObjectSpace::WeakMap#size" do
    ObjectSpace::WeakMap.instance_method(:length).should ==
      ObjectSpace::WeakMap.instance_method(:size)
  end
end
