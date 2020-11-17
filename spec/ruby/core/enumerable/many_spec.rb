require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.0" do
  describe "Enumerable#many?" do
    before :each do
      @empty = EnumerableSpecs::Empty.new
      @enum = EnumerableSpecs::Numerous.new
      @enum1 = EnumerableSpecs::Numerous.new(0, 1, 2, -1)
      @enum2 = EnumerableSpecs::Numerous.new(nil, false, true)
    end

    it "always returns false on empty enumeration" do
      @empty.should_not.many?
      @empty.many? { true }.should == false
    end

    it "raises an ArgumentError when more than 1 argument is provided" do
      -> { @enum.many?(1, 2, 3) }.should raise_error(ArgumentError)
      -> { [].many?(1, 2, 3) }.should raise_error(ArgumentError)
      -> { {}.many?(1, 2, 3) }.should raise_error(ArgumentError)
    end

    it "does not hide exceptions out of #each" do
      -> {
        EnumerableSpecs::ThrowingEach.new.many?
      }.should raise_error(RuntimeError)

      -> {
        EnumerableSpecs::ThrowingEach.new.many? { false }
      }.should raise_error(RuntimeError)
    end

    describe "with no block" do
      it "returns false if only one element evaluates to true" do
        [false, nil, true].many?.should be_false
      end

      it "returns true if two elements evaluate to true" do
        [false, :value, nil, true].many?.should be_true
      end

      it "returns false if all elements evaluate to false" do
        [false, nil, false].many?.should be_false
      end

      it "gathers whole arrays as elements when each yields multiple" do
        multi = EnumerableSpecs::YieldsMultiWithSingleTrue.new
        multi.many?.should be_true
      end
    end

    describe "with a block" do
      it "returns false if block returns true once" do
        [:a, :b, :c].many? { |s| s == :a }.should be_false
      end

      it "returns true if the block returns true more than once" do
        [:a, :b, :c].many? { |s| s == :a || s == :b }.should be_true
      end

      it "returns false if the block only returns false" do
        [:a, :b, :c].many? { |s| s == :d }.should be_false
      end

      it "does not hide exceptions out of the block" do
        -> {
          @enum.many? { raise "from block" }
        }.should raise_error(RuntimeError)
      end

      it "gathers initial args as elements when each yields multiple" do
        multi = EnumerableSpecs::YieldsMulti.new
        yielded = []
        multi.many? { |e| yielded << e; false }.should be_false
        yielded.should == [1, 3, 6]
      end

      it "yields multiple arguments when each yields multiple" do
        multi = EnumerableSpecs::YieldsMulti.new
        yielded = []
        multi.many? { |*args| yielded << args; false }.should be_false
        yielded.should == [[1, 2], [3, 4, 5], [6, 7, 8, 9]]
      end

      it "calls blocks until the second truthy return value" do
        called = []
        [1, 2, 3].many? {|i| called << i ; i }
        called.should == [1, 2]
      end
    end

    describe 'when given a pattern argument' do
      it "calls `===` on the pattern the return value " do
        pattern = EnumerableSpecs::Pattern.new { |x| x == 1 }
        @enum1.many?(pattern).should be_false
        pattern.yielded.should == [[0], [1], [2], [-1]]
      end

      # may raise an exception in future versions
      ruby_version_is ""..."2.6" do
        it "ignores block" do
          @enum2.many?(NilClass) { raise }.should be_false
          [1, 2, nil].many?(Integer) { raise }.should be_true
          {a: 1, b: 2}.many?(Array) { raise }.should be_true
        end
      end

      it "always returns false on empty enumeration" do
        @empty.many?(Integer).should be_false
        [].many?(Integer).should be_false
        {}.many?(NilClass).should be_false
      end

      it "does not hide exceptions out of #each" do
        -> {
          EnumerableSpecs::ThrowingEach.new.many?(Integer)
        }.should raise_error(RuntimeError)
      end

      it "returns false if the pattern returns a truthy value only once" do
        @enum2.many?(NilClass).should be_false
        pattern = EnumerableSpecs::Pattern.new { |x| x == 2 }
        @enum1.many?(pattern).should be_false

        [1, 2, 42, 3].many?(pattern).should be_false

        pattern = EnumerableSpecs::Pattern.new { |x| x == [:b, 2] }
        {a: 1, b: 2}.many?(pattern).should be_false
      end

      it "returns true if the pattern returns a truthy value more than once" do
        pattern = EnumerableSpecs::Pattern.new { |x| !x }
        @enum2.many?(pattern).should be_true
        pattern.yielded.should == [[nil], [false]]

        [1, 2, 3].many?(Integer).should be_true
        {a: 1, b: 2}.many?(Array).should be_true
      end

      it "returns false if the pattern never returns a truthy value" do
        pattern = EnumerableSpecs::Pattern.new { |x| nil }
        @enum1.many?(pattern).should be_false
        pattern.yielded.should == [[0], [1], [2], [-1]]

        [1, 2, 3].many?(pattern).should be_false
        {a: 1}.many?(pattern).should be_false
      end

      it "does not hide exceptions out of pattern#===" do
        pattern = EnumerableSpecs::Pattern.new { raise "from pattern" }
        -> {
          @enum.many?(pattern)
        }.should raise_error(RuntimeError)
      end

      it "calls the pattern with gathered array when yielded with multiple arguments" do
        multi = EnumerableSpecs::YieldsMulti.new
        pattern = EnumerableSpecs::Pattern.new { false }
        multi.many?(pattern).should be_false
        pattern.yielded.should == [[[1, 2]], [[3, 4, 5]], [[6, 7, 8, 9]]]
      end
    end
  end
end
