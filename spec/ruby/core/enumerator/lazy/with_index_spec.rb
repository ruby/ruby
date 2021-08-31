# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.7" do
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
  end
end
