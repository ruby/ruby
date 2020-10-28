require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.reachable_objects_from" do
  it "returns nil for true and false" do
    ObjectSpace.reachable_objects_from(true).should == nil
    ObjectSpace.reachable_objects_from(false).should == nil
  end

  it "returns nil for nil" do
    ObjectSpace.reachable_objects_from(nil).should == nil
  end

  it "returns nil for small Integers" do
    ObjectSpace.reachable_objects_from(42).should == nil
  end

  it "enumerates objects directly reachable from a given object" do
    ObjectSpace.reachable_objects_from(['a', 'b', 'c']).should include(Array, 'a', 'b', 'c')
    ObjectSpace.reachable_objects_from(Object.new).should == [Object]
  end

  it "finds an object stored in an Array" do
    obj = Object.new
    ary = [obj]
    reachable = ObjectSpace.reachable_objects_from(ary)
    reachable.should include(obj)
  end

  it "finds an object stored in a copy-on-write Array" do
    removed = Object.new
    obj = Object.new
    ary = [removed, obj]
    ary.shift
    reachable = ObjectSpace.reachable_objects_from(ary)
    reachable.should include(obj)
    reachable.should_not include(removed)
  end

  it "finds an object stored in a Queue" do
    require 'thread'
    o = Object.new
    q = Queue.new
    q << o

    reachable = ObjectSpace.reachable_objects_from(q)
    reachable = reachable + reachable.flat_map { |r| ObjectSpace.reachable_objects_from(r) }
    reachable.should include(o)
  end

  it "finds an object stored in a SizedQueue" do
    require 'thread'
    o = Object.new
    q = SizedQueue.new(3)
    q << o

    reachable = ObjectSpace.reachable_objects_from(q)
    reachable = reachable + reachable.flat_map { |r| ObjectSpace.reachable_objects_from(r) }
    reachable.should include(o)
  end
end
