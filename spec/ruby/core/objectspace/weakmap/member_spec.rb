require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#member?" do
  it "is an alias of ObjectSpace::WeakMap#include?" do
    ObjectSpace::WeakMap.instance_method(:member?).should ==
      ObjectSpace::WeakMap.instance_method(:include?)
  end
end
