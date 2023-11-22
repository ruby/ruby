require_relative '../../spec_helper'
require 'set'

describe "Set#each" do
  before :each do
    @set = Set[1, 2, 3]
  end

  it "yields each Object in self" do
    ret = []
    @set.each { |x| ret << x }
    ret.sort.should == [1, 2, 3]
  end

  it "returns self" do
    @set.each { |x| x }.should equal(@set)
  end

  it "returns an Enumerator when not passed a block" do
    enum = @set.each
    enum.should be_an_instance_of(Enumerator)

    ret = []
    enum.each { |x| ret << x }
    ret.sort.should == [1, 2, 3]
  end
end
