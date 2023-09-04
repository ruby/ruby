require_relative '../../../spec_helper'

ruby_version_is "3.2" do
  describe "Enumerator::Product#inspect" do
    it "returns a String including enumerators" do
      enum = Enumerator::Product.new([1, 2], [:a, :b])
      enum.inspect.should == "#<Enumerator::Product: [[1, 2], [:a, :b]]>"
    end

    it "represents a recursive element with '[...]'" do
      enum = [1, 2]
      enum_recursive = Enumerator::Product.new(enum)

      enum << enum_recursive
      enum_recursive.inspect.should == "#<Enumerator::Product: [[1, 2, #<Enumerator::Product: ...>]]>"
    end

    it "returns a not initialized representation if #initialized is not called yet" do
      Enumerator::Product.allocate.inspect.should == "#<Enumerator::Product: uninitialized>"
    end
  end
end
