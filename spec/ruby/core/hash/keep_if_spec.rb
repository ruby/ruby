require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/iteration'
require_relative '../enumerable/shared/enumeratorized'

describe "Hash#keep_if" do
  it "yields two arguments: key and value" do
    all_args = []
    { 1 => 2, 3 => 4 }.keep_if { |*args| all_args << args }
    all_args.should == [[1, 2], [3, 4]]
  end

  it "keeps every entry for which block is true and returns self" do
    h = { a: 1, b: 2, c: 3, d: 4 }
    h.keep_if { |k,v| v % 2 == 0 }.should equal(h)
    h.should == { b: 2, d: 4 }
  end

  it "removes all entries if the block is false" do
    h = { a: 1, b: 2, c: 3 }
    h.keep_if { |k,v| false }.should equal(h)
    h.should == {}
  end

  it "returns self even if unmodified" do
    h = { 1 => 2, 3 => 4 }
    h.keep_if { true }.should equal(h)
  end

  it "raises a #{frozen_error_class} if called on a frozen instance" do
    -> { HashSpecs.frozen_hash.keep_if { true } }.should raise_error(frozen_error_class)
    -> { HashSpecs.empty_frozen_hash.keep_if { false } }.should raise_error(frozen_error_class)
  end

  it_behaves_like :hash_iteration_no_block, :keep_if
  it_behaves_like :enumeratorized_with_origin_size, :keep_if, { 1 => 2, 3 => 4, 5 => 6 }
end
