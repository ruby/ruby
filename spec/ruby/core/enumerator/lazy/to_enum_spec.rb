require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#to_enum" do
  before :each do
    @infinite = (0..Float::INFINITY).lazy
  end

  it "requires multiple arguments" do
    Enumerator::Lazy.instance_method(:to_enum).arity.should < 0
  end

  it "returns a new instance of Enumerator::Lazy" do
    ret = @infinite.to_enum
    ret.should.instance_of?(Enumerator::Lazy)
    ret.should_not.equal?(@infinite)
  end

  it "sets #size to nil when not given a block" do
    Enumerator::Lazy.new(Object.new, 100) {}.to_enum.size.should == nil
  end

  it "sets given block to size when given a block" do
    Enumerator::Lazy.new(Object.new, 100) {}.to_enum { 30 }.size.should == 30
  end

  it "generates a lazy enumerator from the given name" do
    @infinite.to_enum(:with_index, 10).first(3).should == [[0, 10], [1, 11], [2, 12]]
  end

  it "passes given arguments to wrapped method" do
    @infinite.to_enum(:each_slice, 2).map { |assoc| assoc.first * assoc.last }.first(4).should == [0, 6, 20, 42]
  end

  it "used by some parent's methods though returning Lazy" do
    { each_with_index: [],
      with_index: [],
      cycle: [1],
      each_with_object: [Object.new],
      with_object: [Object.new],
      each_slice: [2],
      each_entry: [],
      each_cons: [2]
    }.each_pair do |method, args|
      @infinite.send(method, *args).should.instance_of?(Enumerator::Lazy)
    end
  end

  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.to_enum(:with_index).first(100).should ==
      s.first(100).to_enum.to_enum(:with_index).to_a
  end
end
