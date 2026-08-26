require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../enumerable/shared/enumeratorized'

# Modifying a collection while the contents are being iterated
# gives undefined behavior. See
# https://blade.ruby-lang.org/ruby-core/23633

ruby_version_is "4.0" do
  describe "Array#find" do
    it "returns the first element for which the block is not false" do
      [1, 2, 3, 4, 5].find { |x| x % 2 == 0 }.should == 2
    end

    it "returns nil when the block is false and there is no ifnone proc given" do
      [1, 2, 3].find { |x| false }.should == nil
    end

    it "returns the value of the ifnone proc if the block is false" do
      fail_proc = -> { "cheeseburgers" }
      [1, 2, 3].find(fail_proc) { |x| false }.should == "cheeseburgers"
    end

    it "doesn't call the ifnone proc if an element is found" do
      fail_proc = -> { raise "This shouldn't have been called" }
      [1, 2, 3].find(fail_proc) { |x| x == 1 }.should == 1
    end

    it "calls the ifnone proc only once when the block is false" do
      times = 0
      fail_proc = -> { times += 1; raise if times > 1; "cheeseburgers" }
      [1, 2, 3].find(fail_proc) { |x| false }.should == "cheeseburgers"
    end

    it "calls the ifnone proc when there are no elements" do
      fail_proc = -> { "yay" }
      [].find(fail_proc) { |x| true }.should == "yay"
    end

    it "ignores the ifnone argument when nil" do
      [1, 2, 3].find(nil) { |x| false }.should == nil
    end

    it "raises a NoMethodError if the ifnone argument does not respond to #call and no element is found" do
      -> { [1, 2, 3].find(42) { |x| false } }.should.raise(NoMethodError)
    end

    it "iterates elements in forward order" do
      visited = []
      [1, 2, 3].find { |element| visited << element; false }
      visited.should == [1, 2, 3]
    end

    it "passes through the values yielded by #each_with_index" do
      ScratchPad.record []
      [:a, :b].each_with_index.to_a.find { |x, i| ScratchPad << [x, i]; nil }
      ScratchPad.recorded.should == [[:a, 0], [:b, 1]]
    end

    it "stops iterating as soon as an element is found" do
      visited = []
      [1, 2, 3, 4, 5].find { |x| visited << x; x == 3 }
      visited.should == [1, 2, 3]
    end

    it "returns an enumerator when no block given" do
      [1, 2, 3].find.should.instance_of?(Enumerator)
    end

    it "passes the ifnone proc to the enumerator" do
      fail_proc = -> { "cheeseburgers" }
      enum = [1, 2, 3].find(fail_proc)
      enum.each { |x| false }.should == "cheeseburgers"
    end

    it "does not destructure elements" do
      multi = [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
      multi.find { |e| e == [1, 2] }.should == [1, 2]
    end

    it "rechecks the array size during iteration" do
      ary = [4, 2, 1, 5, 1, 3]
      seen = []
      ary.find { |x| seen << x; ary.clear; false }
      seen.should == [4]
    end

    it_behaves_like :enumeratorized_with_unknown_size, :find, [1, 2, 3]
  end
end
