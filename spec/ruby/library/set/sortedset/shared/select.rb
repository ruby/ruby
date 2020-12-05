require_relative '../../../../spec_helper'
require 'set'

describe :sorted_set_select_bang, shared: true do
  before :each do
    @set = SortedSet["one", "two", "three"]
  end

  it "yields each Object in self in sorted order" do
    res = []
    @set.send(@method) { |x| res << x }
    res.should == ["one", "two", "three"].sort
  end

  it "keeps every element from self for which the passed block returns true" do
    @set.send(@method) { |x| x.size != 3 }
    @set.to_a.should == ["three"]
  end

  it "returns self when self was modified" do
    @set.send(@method) { false }.should equal(@set)
  end

  it "returns nil when self was not modified" do
    @set.send(@method) { true }.should be_nil
  end

  it "returns an Enumerator when passed no block" do
    enum = @set.send(@method)
    enum.should be_an_instance_of(Enumerator)

    enum.each { |x| x.size != 3 }
    @set.to_a.should == ["three"]
  end
end
