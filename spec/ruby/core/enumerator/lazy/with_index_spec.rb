# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#with_index" do
  it "enumerates with an index" do
    (0..Float::INFINITY).lazy.with_index.map { |i, idx| [i, idx] }.first(3).should == [[0, 0], [1, 1], [2, 2]]
  end

  it "enumerates with an index starting at a given offset" do
    (0..Float::INFINITY).lazy.with_index(3).map { |i, idx| [i, idx] }.first(3).should == [[0, 3], [1, 4], [2, 5]]
  end

  it "enumerates with an index starting at 0 when offset is nil" do
    (0..Float::INFINITY).lazy.with_index(nil).map { |i, idx| [i, idx] }.first(3).should == [[0, 0], [1, 1], [2, 2]]
  end

  it "raises TypeError when offset does not convert to Integer" do
    -> { (0..Float::INFINITY).lazy.with_index(false).map { |i, idx| i }.first(3) }.should raise_error(TypeError)
  end

  it "enumerates with a given block" do
    result = []
    (0..Float::INFINITY).lazy.with_index { |i, idx| result << [i * 2, idx] }.first(3)
    result.should == [[0,0],[2,1],[4,2]]
  end

  it "resets after a new call to each" do
    enum = (0..2).lazy.with_index.map { |i, idx| [i, idx] }
    result = []
    enum.each { |i, idx| result << [i, idx] }
    enum.each { |i, idx| result << [i, idx] }
    result.should == [[0,0], [1,1], [2,2], [0,0], [1,1], [2,2]]
  end
end
