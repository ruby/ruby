require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/iteration'
require_relative '../enumerable/shared/enumeratorized'

describe "Hash#each_value" do
  it "calls block once for each key, passing value" do
    r = []
    h = { a: -5, b: -3, c: -2, d: -1, e: -1 }
    h.each_value { |v| r << v }.should equal(h)
    r.sort.should == [-5, -3, -2, -1, -1]
  end

  it "processes values in the same order as values()" do
    values = []
    h = { a: -5, b: -3, c: -2, d: -1, e: -1 }
    h.each_value { |v| values << v }
    values.should == h.values
  end

  it_behaves_like :hash_iteration_no_block, :each_value
  it_behaves_like :enumeratorized_with_origin_size, :each_value, { 1 => 2, 3 => 4, 5 => 6 }
end
