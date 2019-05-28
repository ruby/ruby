require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.memsize_of" do
  it "returns 0 for true, false and nil" do
    ObjectSpace.memsize_of(true).should == 0
    ObjectSpace.memsize_of(false).should == 0
    ObjectSpace.memsize_of(nil).should == 0
  end

  it "returns 0 for small Integers" do
    ObjectSpace.memsize_of(42).should == 0
  end

  it "returns an Integer for an Object" do
    obj = Object.new
    ObjectSpace.memsize_of(obj).should be_kind_of(Integer)
    ObjectSpace.memsize_of(obj).should > 0
  end

  it "is larger if the Object has more instance variables" do
    obj = Object.new
    before = ObjectSpace.memsize_of(obj)
    100.times do |i|
      obj.instance_variable_set(:"@foo#{i}", nil)
    end
    after = ObjectSpace.memsize_of(obj)
    after.should > before
  end
end
