require_relative '../../../spec_helper'

describe "Enumerator::Lazy#slice_when" do
  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.slice_when { |a, b| true }.first(100).should ==
      s.first(100).slice_when { |a, b| true }.to_a
  end

  it "should return a lazy enumerator" do
    s = 0..Float::INFINITY
    s.lazy.slice_when { |a, b| true }.should be_kind_of(Enumerator::Lazy)
  end
end
