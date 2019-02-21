require_relative '../../../spec_helper'

describe "Enumerator::Lazy#slice_before" do
  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.slice_before { |n| true }.first(100).should ==
      s.first(100).slice_before { |n| true }.to_a
  end
end
