require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.memsize_of_all" do
  it "returns a non-zero Integer for all objects" do
    ObjectSpace.memsize_of_all.should be_kind_of(Integer)
    ObjectSpace.memsize_of_all.should > 0
  end

  it "returns a non-zero Integer for Class" do
    ObjectSpace.memsize_of_all(Class).should be_kind_of(Integer)
    ObjectSpace.memsize_of_all(Class).should > 0
  end

  it "increases when a new object is allocated" do
    before = ObjectSpace.memsize_of_all(Class)
    o = Class.new
    after = ObjectSpace.memsize_of_all(Class)
    after.should > before
  end
end
