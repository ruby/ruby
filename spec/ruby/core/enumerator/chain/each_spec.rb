require_relative '../../../spec_helper'
require_relative '../../enumerable/fixtures/classes'

describe "Enumerator::Chain#each" do
  it "calls each on its constituents as needed" do
    a = EnumerableSpecs::EachCounter.new(:a, :b)
    b = EnumerableSpecs::EachCounter.new(:c, :d)

    ScratchPad.record []
    Enumerator::Chain.new(a, b).each do |elem|
      ScratchPad << elem << b.times_yielded
    end
    ScratchPad.recorded.should == [:a, 0, :b, 0, :c, 1, :d, 2]
  end
end
