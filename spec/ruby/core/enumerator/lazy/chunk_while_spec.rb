require_relative '../../../spec_helper'

describe "Enumerator::Lazy#chunk_while" do
  it "works with an infinite enumerable" do
    s = 0..Float::INFINITY
    s.lazy.chunk_while { |a, b| false }.first(100).should ==
      s.first(100).chunk_while { |a, b| false }.to_a
  end

  it "should return a lazy enumerator" do
    s = 0..Float::INFINITY
    s.lazy.chunk_while { |a, b| false }.should be_kind_of(Enumerator::Lazy)
  end
end
