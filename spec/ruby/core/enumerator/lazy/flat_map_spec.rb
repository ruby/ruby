# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/collect_concat'

describe "Enumerator::Lazy#flat_map" do
  it_behaves_like :enumerator_lazy_collect_concat, :flat_map

  it "properly unwraps nested yields" do
    s = Enumerator.new do |y| loop do y << [1, 2] end end

    expected = s.take(3).flat_map { |x| x }.to_a
    actual = s.lazy.take(3).flat_map{ |x| x }.force
    actual.should == expected
  end
end
