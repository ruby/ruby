require_relative '../../../spec_helper'
require_relative '../../enumerable/shared/enumeratorized'

ruby_version_is "3.2" do
  describe "Enumerator::Product#each" do
    it_behaves_like :enumeratorized_with_origin_size, :each, Enumerator::Product.new([1, 2], [:a, :b])

    it "yields each element of Cartesian product of enumerators" do
      enum = Enumerator::Product.new([1, 2], [:a, :b])
      acc = []
      enum.each { |e| acc << e }
      acc.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
    end

    it "calls #each_entry method on enumerators" do
      object1 = Object.new
      def object1.each_entry
        yield 1
        yield 2
      end

      object2 = Object.new
      def object2.each_entry
        yield :a
        yield :b
      end

      enum = Enumerator::Product.new(object1, object2)
      acc = []
      enum.each { |e| acc << e }
      acc.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
    end

    it "raises a NoMethodError if the object doesn't respond to #each_entry" do
      -> {
        Enumerator::Product.new(Object.new).each {}
      }.should raise_error(NoMethodError, /undefined method [`']each_entry' for/)
    end

    it "returns enumerator if not given a block" do
      enum = Enumerator::Product.new([1, 2], [:a, :b])
      enum.each.should.kind_of?(Enumerator)

      enum = Enumerator::Product.new([1, 2], [:a, :b])
      enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
    end

    it "returns self if given a block" do
      enum = Enumerator::Product.new([1, 2], [:a, :b])
      enum.each {}.should.equal?(enum)
    end

    it "doesn't accept arguments" do
      Enumerator::Product.instance_method(:each).arity.should == 0
    end

    it "yields each element to a block that takes multiple arguments" do
      enum = Enumerator::Product.new([1, 2], [:a, :b])

      acc = []
      enum.each { |x, y| acc << x }
      acc.should == [1, 1, 2, 2]

      acc = []
      enum.each { |x, y| acc << y }
      acc.should == [:a, :b, :a, :b]

      acc = []
      enum.each { |x, y, z| acc << z }
      acc.should == [nil, nil, nil, nil]
    end
  end
end
