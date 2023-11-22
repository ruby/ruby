require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#zip" do

  it "combines each element of the receiver with the element of the same index in arrays given as arguments" do
    EnumerableSpecs::Numerous.new(1,2,3).zip([4,5,6],[7,8,9]).should == [[1,4,7],[2,5,8],[3,6,9]]
    EnumerableSpecs::Numerous.new(1,2,3).zip.should == [[1],[2],[3]]
  end

  it "passes each element of the result array to a block and return nil if a block is given" do
    expected = [[1,4,7],[2,5,8],[3,6,9]]
    EnumerableSpecs::Numerous.new(1,2,3).zip([4,5,6],[7,8,9]) do |result_component|
      result_component.should == expected.shift
    end.should == nil
    expected.size.should == 0
  end

  it "fills resulting array with nils if an argument array is too short" do
    EnumerableSpecs::Numerous.new(1,2,3).zip([4,5,6], [7,8]).should == [[1,4,7],[2,5,8],[3,6,nil]]
  end

  it "converts arguments to arrays using #to_ary" do
    convertible = EnumerableSpecs::ArrayConvertible.new(4,5,6)
    EnumerableSpecs::Numerous.new(1,2,3).zip(convertible).should == [[1,4],[2,5],[3,6]]
    convertible.called.should == :to_ary
  end

  it "converts arguments to enums using #to_enum" do
    convertible = EnumerableSpecs::EnumConvertible.new(4..6)
    EnumerableSpecs::Numerous.new(1,2,3).zip(convertible).should == [[1,4],[2,5],[3,6]]
    convertible.called.should == :to_enum
    convertible.sym.should == :each
  end

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.zip(multi).should == [[[1, 2], [1, 2]], [[3, 4, 5], [3, 4, 5]], [[6, 7, 8, 9], [6, 7, 8, 9]]]
  end

  it "raises TypeError when some argument isn't Array and doesn't respond to #to_ary and #to_enum" do
    -> { EnumerableSpecs::Numerous.new(1,2,3).zip(Object.new) }.should raise_error(TypeError, "wrong argument type Object (must respond to :each)")
    -> { EnumerableSpecs::Numerous.new(1,2,3).zip(1) }.should raise_error(TypeError, "wrong argument type Integer (must respond to :each)")
    -> { EnumerableSpecs::Numerous.new(1,2,3).zip(true) }.should raise_error(TypeError, "wrong argument type TrueClass (must respond to :each)")
  end
end
