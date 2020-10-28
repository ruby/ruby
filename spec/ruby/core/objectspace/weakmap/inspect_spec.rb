require_relative '../../../spec_helper'

describe "ObjectSpace::WeakMap#inspect" do
  it "displays object pointers in output" do
    map = ObjectSpace::WeakMap.new
    # important to test with BasicObject (without Kernel) here to test edge cases
    key1, key2 = [BasicObject.new, Object.new]
    ref1, ref2 = [BasicObject.new, Object.new]
    map.inspect.should =~ /\A\#<ObjectSpace::WeakMap:0x\h+>\z/
    map[key1] = ref1
    map.inspect.should =~ /\A\#<ObjectSpace::WeakMap:0x\h+: \#<BasicObject:0x\h+> => \#<BasicObject:0x\h+>>\z/
    map[key1] = ref1
    map.inspect.should =~ /\A\#<ObjectSpace::WeakMap:0x\h+: \#<BasicObject:0x\h+> => \#<BasicObject:0x\h+>>\z/
    map[key2] = ref2

    regexp1 = /\A\#<ObjectSpace::WeakMap:0x\h+: \#<BasicObject:0x\h+> => \#<BasicObject:0x\h+>, \#<Object:0x\h+> => \#<Object:0x\h+>>\z/
    regexp2 = /\A\#<ObjectSpace::WeakMap:0x\h+: \#<Object:0x\h+> => \#<Object:0x\h+>, \#<BasicObject:0x\h+> => \#<BasicObject:0x\h+>>\z/
    str = map.inspect
    if str =~ regexp1
      str.should =~ regexp1
    else
      str.should =~ regexp2
    end
  end
end
