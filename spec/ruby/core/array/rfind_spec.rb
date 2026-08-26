require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../enumerable/shared/enumeratorized'

# Modifying a collection while the contents are being iterated
# gives undefined behavior. See
# https://blade.ruby-lang.org/ruby-core/23633

ruby_version_is "4.0" do
  describe "Array#rfind" do
    it "returns the last element for which the block is not false" do
      [1, 2, 3, 4, 5].rfind { |x| x % 2 == 0 }.should == 4
    end

    it "returns nil when the block is false and there is no ifnone proc given" do
      [1, 2, 3].rfind { |x| false }.should == nil
    end

    it "returns the value of the ifnone proc if the block is false" do
      fail_proc = -> { "cheeseburgers" }
      [1, 2, 3].rfind(fail_proc) { |x| false }.should == "cheeseburgers"
    end

    it "doesn't call the ifnone proc if an element is found" do
      fail_proc = -> { raise "This shouldn't have been called" }
      [1, 2, 3].rfind(fail_proc) { |x| x == 3 }.should == 3
    end

    it "calls the ifnone proc only once when the block is false" do
      times = 0
      fail_proc = -> { times += 1; raise if times > 1; "cheeseburgers" }
      [1, 2, 3].rfind(fail_proc) { |x| false }.should == "cheeseburgers"
    end

    it "calls the ifnone proc when there are no elements" do
      fail_proc = -> { "yay" }
      [].rfind(fail_proc) { |x| true }.should == "yay"
    end

    it "ignores the ifnone argument when nil" do
      [1, 2, 3].rfind(nil) { |x| false }.should == nil
    end

    it "raises a NoMethodError if the ifnone argument does not respond to #call and no element is found" do
      -> { [1, 2, 3].rfind(42) { |x| false } }.should.raise(NoMethodError)
    end

    it "iterates elements in reverse order" do
      visited = []
      [1, 2, 3].rfind { |x| visited << x; false }
      visited.should == [3, 2, 1]
    end

    it "passes through the values yielded by #each_with_index" do
      ScratchPad.record []
      [:a, :b].each_with_index.to_a.rfind { |x, i| ScratchPad << [x, i]; nil }
      ScratchPad.recorded.should == [[:b, 1], [:a, 0]]
    end

    it "stops iterating as soon as a matching element is found from the end" do
      visited = []
      [1, 2, 3, 4, 5].rfind { |x| visited << x; x == 3 }
      visited.should == [5, 4, 3]
    end

    it "returns an enumerator when no block given" do
      [1, 2, 3].rfind.should.instance_of?(Enumerator)
    end

    it "passes the ifnone proc to the enumerator" do
      fail_proc = -> { "cheeseburgers" }
      enum = [1, 2, 3].rfind(fail_proc)
      enum.each { |x| false }.should == "cheeseburgers"
    end

    it "does not destructure elements" do
      multi = [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
      multi.rfind { |e| e == [1, 2] }.should == [1, 2]
    end

    it "rechecks the array size during iteration" do
      ary = [4, 2, 1, 5, 1, 3]
      seen = []
      ary.rfind { |x| seen << x; ary.clear; false }
      seen.should == [3]
    end

    it_behaves_like :enumeratorized_with_unknown_size, :rfind, [1, 2, 3]
  end
end
