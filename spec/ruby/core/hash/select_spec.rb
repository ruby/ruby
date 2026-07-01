require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'fixtures/classes'
require_relative 'shared/iteration'

describe "Hash#select" do
  before :each do
    @hsh = { 1 => 2, 3 => 4, 5 => 6 }
    @empty = {}
  end

  it "yields two arguments: key and value" do
    all_args = []
    { 1 => 2, 3 => 4 }.select { |*args| all_args << args }
    all_args.sort.should == [[1, 2], [3, 4]]
  end

  it "returns a Hash of entries for which block is true" do
    a_pairs = { 'a' => 9, 'c' => 4, 'b' => 5, 'd' => 2 }.select { |k,v| v % 2 == 0 }
    a_pairs.should.instance_of?(Hash)
    a_pairs.sort.should == [['c', 4], ['d', 2]]
  end

  it "processes entries with the same order as reject" do
    h = { a: 9, c: 4, b: 5, d: 2 }

    select_pairs = []
    reject_pairs = []
    h.dup.select{ |*pair| select_pairs << pair }
    h.reject { |*pair| reject_pairs << pair }

    select_pairs.should == reject_pairs
  end

  it "returns an Enumerator when called on a non-empty hash without a block" do
    @hsh.select.should.instance_of?(Enumerator)
  end

  it "returns an Enumerator when called on an empty hash without a block" do
    @empty.select.should.instance_of?(Enumerator)
  end

  it "does not retain the default value" do
    h = Hash.new(1)
    h.select { true }.default.should == nil
    h[:a] = 1
    h.select { true }.default.should == nil
  end

  it "does not retain the default_proc" do
    pr = proc { |h, k| h[k] = [] }
    h = Hash.new(&pr)
    h.select { true }.default_proc.should == nil
    h[:a] = 1
    h.select { true }.default_proc.should == nil
  end

  it "retains compare_by_identity flag" do
    h = { a: 9, c: 4 }.compare_by_identity
    h2 = h.select { |k, _| k == :a }
    h2.compare_by_identity?.should == true
  end

  it_behaves_like :hash_iteration_no_block, :select

  before :each do
    @object = { 1 => 2, 3 => 4, 5 => 6 }
  end
  it_behaves_like :enumeratorized_with_origin_size, :select
end

describe "Hash#select!" do
  before :each do
    @hsh = { 1 => 2, 3 => 4, 5 => 6 }
    @empty = {}
  end

  it "is equivalent to keep_if if changes are made" do
    h = { a: 2 }
    h.select! { |k,v| v <= 1 }.should.equal? h

    h = { 1 => 2, 3 => 4 }
    all_args_select = []
    h.dup.select! { |*args| all_args_select << args }
    all_args_select.should == [[1, 2], [3, 4]]
  end

  it "removes all entries if the block is false" do
    h = { a: 1, b: 2, c: 3 }
    h.select! { |k,v| false }.should.equal?(h)
    h.should == {}
  end

  it "returns nil if no changes were made" do
    { a: 1 }.select! { |k,v| v <= 1 }.should == nil
  end

  it "raises a FrozenError if called on an empty frozen instance" do
    -> { HashSpecs.empty_frozen_hash.select! { false } }.should.raise(FrozenError)
  end

  it "raises a FrozenError if called on a frozen instance that would not be modified" do
    -> { HashSpecs.frozen_hash.select! { true } }.should.raise(FrozenError)
  end

  it_behaves_like :hash_iteration_no_block, :select!

  before :each do
    @object = { 1 => 2, 3 => 4, 5 => 6 }
  end
  it_behaves_like :enumeratorized_with_origin_size, :select!
end
