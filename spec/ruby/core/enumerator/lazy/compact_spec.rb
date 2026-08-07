require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#compact" do
  # Cannot use shared/value_packing.rb examples: the packed nil is removed by #compact.
  describe "value packing of source yields" do
    it "packs a multi-argument source yield into an Array" do
      e = Enumerator.new { |y| y.yield 1, 2 }
      args = nil
      e.lazy.compact.each { |*a| args = a }
      args.should == [[1, 2]]
    end

    it "removes a zero-argument source yield like nil" do
      e = Enumerator.new { |y| y.yield; y.yield :v }
      collected = []
      e.lazy.compact.each { |*a| collected << a }
      collected.should == [[:v]]
    end
  end

  it 'returns array without nil elements' do
    arr = [1, nil, 3, false, 5].to_enum.lazy.compact
    arr.should.instance_of?(Enumerator::Lazy)
    arr.force.should == [1, 3, false, 5]
  end

  it "sets #size to nil" do
    Enumerator::Lazy.new(Object.new, 100) {}.compact.size.should == nil
  end
end
