require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#merge" do
  it "returns a new hash by combining self with the contents of other" do
    h = { 1 => :a, 2 => :b, 3 => :c }.merge(a: 1, c: 2)
    h.should == { c: 2, 1 => :a, 2 => :b, a: 1, 3 => :c }

    hash = { a: 1, b: 2 }
    {}.merge(hash).should == hash
    hash.merge({}).should == hash

    h = { 1 => :a, 2 => :b, 3 => :c }.merge(1 => :b)
    h.should == { 1 => :b, 2 => :b, 3 => :c }

    h = { 1 => :a, 2 => :b }.merge(1 => :b, 3 => :c)
    h.should == { 1 => :b, 2 => :b, 3 => :c }
  end

  it "sets any duplicate key to the value of block if passed a block" do
    h1 = { a: 2, b: 1, d: 5 }
    h2 = { a: -2, b: 4, c: -3 }
    r = h1.merge(h2) { |k,x,y| nil }
    r.should == { a: nil, b: nil, c: -3, d: 5 }

    r = h1.merge(h2) { |k,x,y| "#{k}:#{x+2*y}" }
    r.should == { a: "a:-2", b: "b:9", c: -3, d: 5 }

    -> {
      h1.merge(h2) { |k, x, y| raise(IndexError) }
    }.should.raise(IndexError)

    r = h1.merge(h1) { |k,x,y| :x }
    r.should == { a: :x, b: :x, d: :x }
  end

  it "tries to convert the passed argument to a hash using #to_hash" do
    obj = mock('{1=>2}')
    obj.should_receive(:to_hash).and_return({ 1 => 2 })
    { 3 => 4 }.merge(obj).should == { 1 => 2, 3 => 4 }
  end

  it "does not call to_hash on hash subclasses" do
    { 3 => 4 }.merge(HashSpecs::ToHashHash[1 => 2]).should == { 1 => 2, 3 => 4 }
  end

  it "returns subclass instance for subclasses" do
    HashSpecs::MyHash[1 => 2, 3 => 4].merge({ 1 => 2 }).should.instance_of?(HashSpecs::MyHash)
    HashSpecs::MyHash[].merge({ 1 => 2 }).should.instance_of?(HashSpecs::MyHash)

    { 1 => 2, 3 => 4 }.merge(HashSpecs::MyHash[1 => 2]).class.should == Hash
    {}.merge(HashSpecs::MyHash[1 => 2]).class.should == Hash
  end

  it "processes entries with same order as each()" do
    h = { 1 => 2, 3 => 4, 5 => 6, "x" => nil, nil => 5, [] => [] }
    merge_pairs = []
    each_pairs = []
    h.each_pair { |k, v| each_pairs << [k, v] }
    h.merge(h) { |k, v1, v2| merge_pairs << [k, v1] }
    merge_pairs.should == each_pairs
  end

  it "preserves the order of merged elements" do
    h1 = { 1 => 2, 3 => 4, 5 => 6 }
    h2 = { 1 => 7 }
    merge_pairs = []
    h1.merge(h2).each_pair { |k, v| merge_pairs << [k, v] }
    merge_pairs.should == [[1,7], [3, 4], [5, 6]]
  end

  it "preserves the order of merged elements for large hashes" do
    h1 = {}
    h2 = {}
    merge_pairs = []
    expected_pairs = []
    (1..100).each { |x| h1[x] = x; h2[101 - x] = x; expected_pairs << [x, 101 - x] }
    h1.merge(h2).each_pair { |k, v| merge_pairs << [k, v] }
    merge_pairs.should == expected_pairs
  end

  it "accepts multiple hashes" do
    result = { a: 1 }.merge({ b: 2 }, { c: 3 }, { d: 4 })
    result.should == { a: 1, b: 2, c: 3, d: 4 }
  end

  it "accepts zero arguments and returns a copy of self" do
    hash = { a: 1 }
    merged = hash.merge

    merged.should.eql?(hash)
    merged.should_not.equal?(hash)
  end

  it "retains the default value" do
    h = Hash.new(1)
    h.merge(b: 1, d: 2).default.should == 1
  end

  it "retains the default_proc" do
    pr = proc { |h, k| h[k] = [] }
    h = Hash.new(&pr)
    h.merge(b: 1, d: 2).default_proc.should == pr
  end

  it "retains compare_by_identity flag" do
    h = { a: 9, c: 4 }.compare_by_identity
    h2 = h.merge(b: 1, d: 2)
    h2.compare_by_identity?.should == true
  end

  it "ignores compare_by_identity flag of an argument" do
    h = { a: 9, c: 4 }.compare_by_identity
    h2 = { b: 1, d: 2 }.merge(h)
    h2.compare_by_identity?.should == false
  end
end

describe "Hash#merge!" do
  it "adds the entries from other, overwriting duplicate keys. Returns self" do
    h = { _1: 'a', _2: '3' }
    h.merge!(_1: '9', _9: 2).should.equal?(h)
    h.should == { _1: "9", _2: "3", _9: 2 }
  end

  it "sets any duplicate key to the value of block if passed a block" do
    h1 = { a: 2, b: -1 }
    h2 = { a: -2, c: 1 }
    h1.merge!(h2) { |k,x,y| 3.14 }.should.equal?(h1)
    h1.should == { c: 1, b: -1, a: 3.14 }

    h1.merge!(h1) { nil }
    h1.should == { a: nil, b: nil, c: nil }
  end

  it "tries to convert the passed argument to a hash using #to_hash" do
    obj = mock('{1=>2}')
    obj.should_receive(:to_hash).and_return({ 1 => 2 })
    { 3 => 4 }.merge!(obj).should == { 1 => 2, 3 => 4 }
  end

  it "does not call to_hash on hash subclasses" do
    { 3 => 4 }.merge!(HashSpecs::ToHashHash[1 => 2]).should == { 1 => 2, 3 => 4 }
  end

  it "processes entries with same order as merge()" do
    h = { 1 => 2, 3 => 4, 5 => 6, "x" => nil, nil => 5, [] => [] }
    merge_bang_pairs = []
    merge_pairs = []
    h.merge(h) { |*arg| merge_pairs << arg }
    h.merge!(h) { |*arg| merge_bang_pairs << arg }
    merge_bang_pairs.should == merge_pairs
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> do
      HashSpecs.frozen_hash.merge!(1 => 2)
    end.should.raise(FrozenError)
  end

  it "checks frozen status before coercing an object with #to_hash" do
    obj = mock("to_hash frozen")
    # This is necessary because mock cleanup code cannot run on the frozen
    # object.
    def obj.to_hash() raise Exception, "should not receive #to_hash" end
    obj.freeze

    -> { HashSpecs.frozen_hash.merge!(obj) }.should.raise(FrozenError)
  end

  # see redmine #1571
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> do
      HashSpecs.frozen_hash.merge!(HashSpecs.empty_frozen_hash)
    end.should.raise(FrozenError)
  end

  it "does not raise an exception if changing the value of an existing key during iteration" do
    hash = {1 => 2, 3 => 4, 5 => 6}
    hash2 = {1 => :foo, 3 => :bar}
    hash.each { hash.merge!(hash2) }
    hash.should == {1 => :foo, 3 => :bar, 5 => 6}
  end

  it "accepts multiple hashes" do
    result = { a: 1 }.merge!({ b: 2 }, { c: 3 }, { d: 4 })
    result.should == { a: 1, b: 2, c: 3, d: 4 }
  end

  it "accepts zero arguments" do
    hash = { a: 1 }
    hash.merge!.should.eql?(hash)
  end
end
