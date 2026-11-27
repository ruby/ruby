require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#ascend" do
  it "yields paths from an absolute path to the root" do
    Pathname.new('/a/b/c').ascend.map(&:to_s).should == ['/a/b/c', '/a/b', '/a', '/']
  end

  it "yields paths from a relative path to its first component" do
    Pathname.new('a/b/c').ascend.map(&:to_s).should == ['a/b/c', 'a/b', 'a']
  end

  it "preserves an explicit current directory prefix" do
    Pathname.new('./a/b/c').ascend.map(&:to_s).should == ['./a/b/c', './a/b', './a', '.']
  end

  it "preserves a trailing separator on the first path" do
    Pathname.new('a/').ascend.map(&:to_s).should == ['a/']
  end

  it "returns nil when given a block" do
    Pathname.new('a/b').ascend { |_| }.should == nil
  end

  it "returns an Enumerator without a block" do
    Pathname.new('a').ascend.should.is_a?(Enumerator)
  end
end
