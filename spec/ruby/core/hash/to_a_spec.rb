require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#to_a" do
  it "returns a list of [key, value] pairs with same order as each()" do
    h = { a: 1, 1 => :a, 3 => :b, b: 5 }
    pairs = []

    h.each_pair do |key, value|
      pairs << [key, value]
    end

    h.to_a.should.is_a?(Array)
    h.to_a.should == pairs
  end

  it "is called for Enumerable#entries" do
    h = { a: 1, 1 => :a, 3 => :b, b: 5 }
    pairs = []

    h.each_pair do |key, value|
      pairs << [key, value]
    end

    ent = h.entries
    ent.should.is_a?(Array)
    ent.should == pairs
  end
end
