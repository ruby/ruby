require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#key?" do
  it "is an alias of ObjectSpace::WeakMap#include?" do
    ObjectSpace::WeakMap.instance_method(:key?).should ==
      ObjectSpace::WeakMap.instance_method(:include?)
  end
end
