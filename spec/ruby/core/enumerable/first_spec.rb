require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/take'

describe "Enumerable#first" do
  it "returns the first element" do
    EnumerableSpecs::Numerous.new.first.should == 2
    EnumerableSpecs::Empty.new.first.should == nil
  end

  it "returns nil if self is empty" do
    EnumerableSpecs::Empty.new.first.should == nil
  end

  it 'returns a gathered array from yield parameters' do
    EnumerableSpecs::YieldsMulti.new.to_enum.first.should == [1, 2]
    EnumerableSpecs::YieldsMixed2.new.to_enum.first.should == nil
  end

  it "raises a RangeError when passed a Bignum" do
    enum = EnumerableSpecs::Empty.new
    -> { enum.first(bignum_value) }.should raise_error(RangeError)
  end

  describe "when passed an argument" do
    it_behaves_like :enumerable_take, :first
  end
end
