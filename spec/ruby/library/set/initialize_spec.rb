require_relative '../../spec_helper'
require 'set'

describe "Set#initialize" do
  it "is private" do
    Set.should have_private_instance_method(:initialize)
  end

  it "adds all elements of the passed Enumerable to self" do
    s = Set.new([1, 2, 3])
    s.size.should eql(3)
    s.should include(1)
    s.should include(2)
    s.should include(3)
  end

  it "should initialize with empty array and set" do
    s = Set.new([])
    s.size.should eql(0)

    s = Set.new({})
    s.size.should eql(0)
  end

  it "preprocesses all elements by a passed block before adding to self" do
    s = Set.new([1, 2, 3]) { |x| x * x }
    s.size.should eql(3)
    s.should include(1)
    s.should include(4)
    s.should include(9)
  end

  it "should initialize with empty array and block" do
    s = Set.new([]) { |x| x * x }
    s.size.should eql(0)
  end

  it "should initialize with empty set and block" do
    s = Set.new(Set.new) { |x| x * x }
    s.size.should eql(0)
  end

  it "should initialize with just block" do
    s = Set.new { |x| x * x }
    s.size.should eql(0)
    s.should eql(Set.new)
  end
end
