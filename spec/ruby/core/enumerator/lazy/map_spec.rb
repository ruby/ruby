# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'
require_relative 'shared/collect'

describe "Enumerator::Lazy#map" do
  it_behaves_like :enumerator_lazy_collect, :map

  it "doesn't unwrap Arrays" do
    Enumerator.new {|y| y.yield([1])}.lazy.to_a.should == [[1]]
  end
end
