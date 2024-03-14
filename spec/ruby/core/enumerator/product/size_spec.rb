require_relative '../../../spec_helper'

ruby_version_is "3.2" do
  describe "Enumerator::Product#size" do
    it "returns the total size of the enumerator product calculated by multiplying the sizes of enumerables in the product" do
      product = Enumerator::Product.new(1..2, 1..3, 1..4)
      product.size.should == 24 # 2 * 3 * 4
    end

    it "returns nil if any enumerable reports its size as nil" do
      enum = Object.new
      def enum.size; nil; end

      product = Enumerator::Product.new(1..2, enum)
      product.size.should == nil
    end

    it "returns Float::INFINITY if any enumerable reports its size as Float::INFINITY" do
      enum = Object.new
      def enum.size; Float::INFINITY; end

      product = Enumerator::Product.new(1..2, enum)
      product.size.should == Float::INFINITY
    end

    it "returns nil if any enumerable reports its size as Float::NAN" do
      enum = Object.new
      def enum.size; Float::NAN; end

      product = Enumerator::Product.new(1..2, enum)
      product.size.should == nil
    end

    it "returns nil if any enumerable doesn't respond to #size" do
      enum = Object.new
      product = Enumerator::Product.new(1..2, enum)
      product.size.should == nil
    end

    it "returns nil if any enumerable reports a not-convertible to Integer" do
      enum = Object.new
      def enum.size; :symbol; end

      product = Enumerator::Product.new(1..2, enum)
      product.size.should == nil
    end

    it "returns nil if any enumerable reports a non-Integer but convertible to Integer size" do
      enum = Object.new
      def enum.size; 1.0; end

      product = Enumerator::Product.new(1..2, enum)
      product.size.should == nil
    end
  end
end
