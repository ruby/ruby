# -*- encoding: us-ascii -*-

require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#lazy" do
  it "returns an instance of Enumerator::Lazy" do
    EnumerableSpecs::Numerous.new.lazy.should be_an_instance_of(Enumerator::Lazy)
  end
end
