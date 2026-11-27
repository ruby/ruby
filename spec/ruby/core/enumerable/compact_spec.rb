require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#compact" do
  describe "value packing of source yields" do
    it "packs a multi-argument source yield into an Array" do
      e = Enumerator.new { |y| y.yield 1, 2 }
      e.compact.should == [[1, 2]]
    end

    it "removes a zero-argument source yield like nil" do
      e = Enumerator.new { |y| y.yield; y.yield :v }
      e.compact.should == [:v]
    end
  end

  it 'returns array without nil elements' do
    arr = EnumerableSpecs::Numerous.new(nil, 1, 2, nil, true)
    arr.compact.should == [1, 2, true]
  end
end
