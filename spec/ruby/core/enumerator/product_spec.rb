require_relative '../../spec_helper'

ruby_version_is "3.2" do
  describe "Enumerator.product" do
    it "returns a Cartesian product of enumerators" do
      enum = Enumerator.product(1..2, ["A", "B"])
      enum.to_a.should == [[1, "A"], [1, "B"], [2, "A"], [2, "B"]]
    end

    it "accepts a list of enumerators of any length" do
      enum = Enumerator.product(1..2)
      enum.to_a.should == [[1], [2]]

      enum = Enumerator.product(1..2, ["A"])
      enum.to_a.should == [[1, "A"], [2, "A"]]

      enum = Enumerator.product(1..2, ["A"], ["B"])
      enum.to_a.should == [[1, "A", "B"], [2, "A", "B"]]

      enum = Enumerator.product(2..3, ["A"], ["B"], ["C"])
      enum.to_a.should == [[2, "A", "B", "C"], [3, "A", "B", "C"]]
    end

    it "returns an enumerator with an empty array when no arguments passed" do
      enum = Enumerator.product
      enum.to_a.should == [[]]
    end

    it "returns an instance of Enumerator::Product" do
      enum = Enumerator.product
      enum.class.should == Enumerator::Product
    end

    it "accepts infinite enumerators and returns infinite enumerator" do
      enum = Enumerator.product(1.., ["A", "B"])
      enum.take(5).should == [[1, "A"], [1, "B"], [2, "A"], [2, "B"], [3, "A"]]
      enum.size.should == Float::INFINITY
    end

    it "accepts a block" do
      elems = []
      enum = Enumerator.product(1..2, ["X", "Y"]) { elems << _1 }

      elems.should == [[1, "X"], [1, "Y"], [2, "X"], [2, "Y"]]
    end

    it "returns nil when a block passed" do
      Enumerator.product(1..2) {}.should == nil
    end

    # https://bugs.ruby-lang.org/issues/19829
    it "reject keyword arguments" do
      -> {
        Enumerator.product(1..3, foo: 1, bar: 2)
      }.should raise_error(ArgumentError, "unknown keywords: :foo, :bar")
    end

    it "calls only #each_entry method on arguments" do
      object = Object.new
      def object.each_entry
        yield 1
        yield 2
      end

      enum = Enumerator.product(object, ["A", "B"])
      enum.to_a.should == [[1, "A"], [1, "B"], [2, "A"], [2, "B"]]
    end

    it "raises NoMethodError when argument doesn't respond to #each_entry" do
      -> {
        Enumerator.product(Object.new).to_a
      }.should raise_error(NoMethodError, /undefined method `each_entry' for/)
    end

    it "calls #each_entry lazily" do
      Enumerator.product(Object.new).should be_kind_of(Enumerator)
    end

    it "iterates through consuming enumerator elements only once" do
      a = [1, 2, 3]
      i = 0

      enum = Enumerator.new do |y|
        while i < a.size
          y << a[i]
          i += 1
        end
      end

      Enumerator.product(['a', 'b'], enum).to_a.should == [["a", 1], ["a", 2], ["a", 3]]
    end
  end
end
