require_relative '../../../spec_helper'

describe "Enumerator::Product#initialize_copy" do
  it "replaces content of the receiver with content of the other object" do
    enum = Enumerator::Product.new([true, false])
    enum2 = Enumerator::Product.new([1, 2], [:a, :b])

    enum.send(:initialize_copy, enum2)
    enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
  end

  it "returns self" do
    enum = Enumerator::Product.new([true, false])
    enum2 = Enumerator::Product.new([1, 2], [:a, :b])

    enum.send(:initialize_copy, enum2).should.equal?(enum)
  end

  it "is a private method" do
    Enumerator::Product.should have_private_instance_method(:initialize_copy, false)
  end

  it "does nothing if the argument is the same as the receiver" do
    enum = Enumerator::Product.new(1..2)
    enum.send(:initialize_copy, enum).should.equal?(enum)

    enum.freeze
    enum.send(:initialize_copy, enum).should.equal?(enum)
  end

  it "raises FrozenError if the receiver is frozen" do
    enum = Enumerator::Product.new(1..2)
    enum2 = Enumerator::Product.new(3..4)

    -> { enum.freeze.send(:initialize_copy, enum2) }.should raise_error(FrozenError)
  end

  it "raises TypeError if the objects are of different class" do
    enum = Enumerator::Product.new(1..2)
    enum2 = Class.new(Enumerator::Product).new(3..4)

    -> { enum.send(:initialize_copy, enum2) }.should raise_error(TypeError, 'initialize_copy should take same class object')
    -> { enum2.send(:initialize_copy, enum) }.should raise_error(TypeError, 'initialize_copy should take same class object')
  end

  it "raises ArgumentError if the argument is not initialized yet" do
    enum = Enumerator::Product.new(1..2)
    enum2 = Enumerator::Product.allocate

    -> { enum.send(:initialize_copy, enum2) }.should raise_error(ArgumentError, 'uninitialized product')
  end
end
