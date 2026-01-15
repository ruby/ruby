require_relative '../../../spec_helper'
require_relative '../../enumerable/fixtures/classes'

describe "Enumerator::Chain#size" do
  it "returns the sum of the sizes of the elements" do
    a = mock('size')
    a.should_receive(:size).and_return(40)
    Enumerator::Chain.new(a, [:a, :b]).size.should == 42
  end

  it "returns nil or Infinity for the first element of such a size" do
    [nil, Float::INFINITY].each do |special|
      a = mock('size')
      a.should_receive(:size).and_return(40)
      b = mock('special')
      b.should_receive(:size).and_return(special)
      c = mock('not called')
      c.should_not_receive(:size)
      Enumerator::Chain.new(a, b, c).size.should == special
    end
  end
end
