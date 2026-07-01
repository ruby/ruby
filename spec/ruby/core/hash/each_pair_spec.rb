require_relative '../../spec_helper'
require_relative 'shared/iteration'
require_relative '../enumerable/shared/enumeratorized'

describe "Hash#each_pair" do
  it_behaves_like :hash_iteration_no_block, :each_pair
  it_behaves_like :enumeratorized_with_origin_size, :each_pair, { 1 => 2, 3 => 4, 5 => 6 }

  # This is inconsistent with below, MRI checks the block arity in rb_hash_each_pair()
  it "yields a [[key, value]] Array for each pair to a block expecting |*args|" do
    all_args = []
    { 1 => 2, 3 => 4 }.each_pair { |*args| all_args << args }
    all_args.sort.should == [[[1, 2]], [[3, 4]]]
  end

  it "yields the key and value of each pair to a block expecting |key, value|" do
    r = {}
    h = { a: 1, b: 2, c: 3, d: 5 }
    h.each_pair { |k,v| r[k.to_s] = v.to_s }.should.equal?(h)
    r.should == { "a" => "1", "b" => "2", "c" => "3", "d" => "5" }
  end

  it "yields the key only to a block expecting |key,|" do
    ary = []
    h = { "a" => 1, "b" => 2, "c" => 3 }
    h.each_pair { |k,| ary << k }
    ary.sort.should == ["a", "b", "c"]
  end

  it "always yields an Array of 2 elements, even when given a callable of arity 2" do
    obj = Object.new
    def obj.foo(key, value)
    end

    -> {
      { "a" => 1 }.each_pair(&obj.method(:foo))
    }.should.raise(ArgumentError)

    -> {
      { "a" => 1 }.each_pair(&-> key, value { })
    }.should.raise(ArgumentError)
  end

  it "yields an Array of 2 elements when given a callable of arity 1" do
    obj = Object.new
    def obj.foo(key_value)
      ScratchPad << key_value
    end

    ScratchPad.record([])
    { "a" => 1 }.each_pair(&obj.method(:foo))
    ScratchPad.recorded.should == [["a", 1]]
  end

  it "raises an error for a Hash when an arity enforcing callable of arity >2 is passed in" do
    obj = Object.new
    def obj.foo(key, value, extra)
    end

    -> {
      { "a" => 1 }.each_pair(&obj.method(:foo))
    }.should.raise(ArgumentError)
  end

  it "uses the same order as keys() and values()" do
    h = { a: 1, b: 2, c: 3, d: 5 }
    keys = []
    values = []

    h.each_pair do |k, v|
      keys << k
      values << v
    end

    keys.should == h.keys
    values.should == h.values
  end

  # Confirming the argument-splatting works from child class for both k, v and [k, v]
  it "properly expands (or not) child class's 'each'-yielded args" do
    cls1 = Class.new(Hash) do
      attr_accessor :k_v
      def each
        super do |k, v|
          @k_v = [k, v]
          yield k, v
        end
      end
    end

    cls2 = Class.new(Hash) do
      attr_accessor :k_v
      def each
        super do |k, v|
          @k_v = [k, v]
          yield([k, v])
        end
      end
    end

    obj1 = cls1.new
    obj1['a'] = 'b'
    obj1.map {|k, v| [k, v]}.should == [['a', 'b']]
    obj1.k_v.should == ['a', 'b']

    obj2 = cls2.new
    obj2['a'] = 'b'
    obj2.map {|k, v| [k, v]}.should == [['a', 'b']]
    obj2.k_v.should == ['a', 'b']
  end
end
