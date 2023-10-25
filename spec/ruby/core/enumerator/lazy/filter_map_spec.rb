# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerator::Lazy#filter_map" do
  it "maps only truthy results" do
    (1..Float::INFINITY).lazy.filter_map { |i| i if i.odd? }.first(4).should == [1, 3, 5, 7]
  end

  it "does not map false results" do
    (1..Float::INFINITY).lazy.filter_map { |i| i.odd? ? i : false }.first(4).should == [1, 3, 5, 7]
  end
end
