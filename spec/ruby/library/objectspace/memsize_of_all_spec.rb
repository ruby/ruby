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
    c = Class.new
    before = ObjectSpace.memsize_of_all(c)
    o = c.new
    after = ObjectSpace.memsize_of_all(c)
    after.should > before
  end
end
