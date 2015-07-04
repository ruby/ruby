require 'test/unit'
EnvUtil.suppress_warning {require 'continuation'}
require 'stringio'

class TestEnumerable < Test::Unit::TestCase
  def setup
    @obj = Object.new
    class << @obj
      include Enumerable
      def each
        yield 1
        yield 2
        yield 3
        yield 1
        yield 2
        self
      end
    end
    @empty = Object.new
    class << @empty
      attr_reader :block
      include Enumerable
      def each(&block)
        @block = block
        self
      end
    end
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_grep_v
    assert_equal([3], @obj.grep_v(1..2))
    a = []
    @obj.grep_v(2) {|x| a << x }
    assert_equal([1, 3, 1], a)

    a = []
    lambda = ->(x, i) {a << [x, i]}
    @obj.each_with_index.grep_v(proc{|x,i|x!=2}, &lambda)
    assert_equal([[2, 1], [2, 4]], a)
  end

  def test_grep
    assert_equal([1, 2, 1, 2], @obj.grep(1..2))
    a = []
    @obj.grep(2) {|x| a << x }
    assert_equal([2, 2], a)

    bug5801 = '[ruby-dev:45041]'
    @empty.grep(//)
    block = @empty.block
    assert_nothing_raised(bug5801) {100.times {block.call}}

    a = []
    lambda = ->(x, i) {a << [x, i]}
    @obj.each_with_index.grep(proc{|x,i|x==2}, &lambda)
    assert_equal([[2, 1], [2, 4]], a)
  end

  def test_count
    assert_equal(5, @obj.count)
    assert_equal(2, @obj.count(1))
    assert_equal(3, @obj.count {|x| x % 2 == 1 })
    assert_equal(2, @obj.count(1) {|x| x % 2 == 1 })
    assert_raise(ArgumentError) { @obj.count(0, 1) }

    if RUBY_ENGINE == "ruby"
      en = Class.new {
        include Enumerable
        alias :size :count
        def each
          yield 1
        end
      }
      assert_equal(1, en.new.count, '[ruby-core:24794]')
    end
  end

  def test_find
    assert_equal(2, @obj.find {|x| x % 2 == 0 })
    assert_equal(nil, @obj.find {|x| false })
    assert_equal(:foo, @obj.find(proc { :foo }) {|x| false })
    cond = ->(x, i) { x % 2 == 0 }
    assert_equal([2, 1], @obj.each_with_index.find(&cond))
  end

  def test_find_index
    assert_equal(1, @obj.find_index(2))
    assert_equal(1, @obj.find_index {|x| x % 2 == 0 })
    assert_equal(nil, @obj.find_index {|x| false })
    assert_raise(ArgumentError) { @obj.find_index(0, 1) }
    assert_equal(1, @obj.find_index(2) {|x| x == 1 })
  end

  def test_find_all
    assert_equal([1, 3, 1], @obj.find_all {|x| x % 2 == 1 })
    cond = ->(x, i) { x % 2 == 1 }
    assert_equal([[1, 0], [3, 2], [1, 3]], @obj.each_with_index.find_all(&cond))
  end

  def test_reject
    assert_equal([2, 3, 2], @obj.reject {|x| x < 2 })
    cond = ->(x, i) {x < 2}
    assert_equal([[2, 1], [3, 2], [2, 4]], @obj.each_with_index.reject(&cond))
  end

  def test_to_a
    assert_equal([1, 2, 3, 1, 2], @obj.to_a)
  end

  def test_to_a_size_symbol
    sym = Object.new
    class << sym
      include Enumerable
      def each
        self
      end

      def size
        :size
      end
    end
    assert_equal([], sym.to_a)
  end

  def test_to_a_size_infinity
    inf = Object.new
    class << inf
      include Enumerable
      def each
        self
      end

      def size
        Float::INFINITY
      end
    end
    assert_equal([], inf.to_a)
  end

  def test_to_h
    obj = Object.new
    def obj.each(*args)
      yield(*args)
      yield [:key, :value]
      yield :other_key, :other_value
      kvp = Object.new
      def kvp.to_ary
        [:obtained, :via_to_ary]
      end
      yield kvp
    end
    obj.extend Enumerable
    assert_equal({
      :hello => :world,
      :key => :value,
      :other_key => :other_value,
      :obtained => :via_to_ary,
    }, obj.to_h(:hello, :world))

    e = assert_raise(TypeError) {
      obj.to_h(:not_an_array)
    }
    assert_equal "wrong element type Symbol (expected array)", e.message

    e = assert_raise(ArgumentError) {
      obj.to_h([1])
    }
    assert_equal "element has wrong array length (expected 2, was 1)", e.message
  end

  def test_inject
    assert_equal(12, @obj.inject {|z, x| z * x })
    assert_equal(48, @obj.inject {|z, x| z * 2 + x })
    assert_equal(12, @obj.inject(:*))
    assert_equal(24, @obj.inject(2) {|z, x| z * x })
    assert_equal(24, @obj.inject(2, :*) {|z, x| z * x })
    assert_equal(nil, @empty.inject() {9})
  end

  def test_partition
    assert_equal([[1, 3, 1], [2, 2]], @obj.partition {|x| x % 2 == 1 })
    cond = ->(x, i) { x % 2 == 1 }
    assert_equal([[[1, 0], [3, 2], [1, 3]], [[2, 1], [2, 4]]], @obj.each_with_index.partition(&cond))
  end

  def test_group_by
    h = { 1 => [1, 1], 2 => [2, 2], 3 => [3] }
    assert_equal(h, @obj.group_by {|x| x })

    h = {1=>[[1, 0], [1, 3]], 2=>[[2, 1], [2, 4]], 3=>[[3, 2]]}
    cond = ->(x, i) { x }
    assert_equal(h, @obj.each_with_index.group_by(&cond))
  end

  def test_first
    assert_equal(1, @obj.first)
    assert_equal([1, 2, 3], @obj.first(3))
    assert_nil(@empty.first)

    bug5801 = '[ruby-dev:45041]'
    assert_in_out_err([], <<-'end;', [], /unexpected break/)
      empty = Object.new
      class << empty
        attr_reader :block
        include Enumerable
        def each(&block)
          @block = block
          self
        end
      end
      empty.first
      empty.block.call
    end;
  end

  def test_sort
    assert_equal([1, 1, 2, 2, 3], @obj.sort)
    assert_equal([3, 2, 2, 1, 1], @obj.sort {|x, y| y <=> x })
  end

  def test_sort_by
    assert_equal([3, 2, 2, 1, 1], @obj.sort_by {|x| -x })
    assert_equal((1..300).to_a.reverse, (1..300).sort_by {|x| -x })

    cond = ->(x, i) { [-x, i] }
    assert_equal([[3, 2], [2, 1], [2, 4], [1, 0], [1, 3]], @obj.each_with_index.sort_by(&cond))
  end

  def test_all
    assert_equal(true, @obj.all? {|x| x <= 3 })
    assert_equal(false, @obj.all? {|x| x < 3 })
    assert_equal(true, @obj.all?)
    assert_equal(false, [true, true, false].all?)
  end

  def test_any
    assert_equal(true, @obj.any? {|x| x >= 3 })
    assert_equal(false, @obj.any? {|x| x > 3 })
    assert_equal(true, @obj.any?)
    assert_equal(false, [false, false, false].any?)
  end

  def test_one
    assert(@obj.one? {|x| x == 3 })
    assert(!(@obj.one? {|x| x == 1 }))
    assert(!(@obj.one? {|x| x == 4 }))
    assert(%w{ant bear cat}.one? {|word| word.length == 4})
    assert(!(%w{ant bear cat}.one? {|word| word.length > 4}))
    assert(!(%w{ant bear cat}.one? {|word| word.length < 4}))
    assert(!([ nil, true, 99 ].one?))
    assert([ nil, true, false ].one?)
  end

  def test_none
    assert(@obj.none? {|x| x == 4 })
    assert(!(@obj.none? {|x| x == 1 }))
    assert(!(@obj.none? {|x| x == 3 }))
    assert(%w{ant bear cat}.none? {|word| word.length == 5})
    assert(!(%w{ant bear cat}.none? {|word| word.length >= 4}))
    assert([].none?)
    assert([nil].none?)
    assert([nil,false].none?)
    assert(![nil,false,true].none?)
  end

  def test_min
    assert_equal(1, @obj.min)
    assert_equal(3, @obj.min {|a,b| b <=> a })
    cond = ->((a, ia), (b, ib)) { (b <=> a).nonzero? or ia <=> ib }
    assert_equal([3, 2], @obj.each_with_index.min(&cond))
    ary = %w(albatross dog horse)
    assert_equal("albatross", ary.min)
    assert_equal("dog", ary.min {|a,b| a.length <=> b.length })
    assert_equal(1, [3,2,1].min)
    assert_equal(%w[albatross dog], ary.min(2))
    assert_equal(%w[dog horse],
                 ary.min(2) {|a,b| a.length <=> b.length })
  end

  def test_max
    assert_equal(3, @obj.max)
    assert_equal(1, @obj.max {|a,b| b <=> a })
    cond = ->((a, ia), (b, ib)) { (b <=> a).nonzero? or ia <=> ib }
    assert_equal([1, 3], @obj.each_with_index.max(&cond))
    ary = %w(albatross dog horse)
    assert_equal("horse", ary.max)
    assert_equal("albatross", ary.max {|a,b| a.length <=> b.length })
    assert_equal(1, [3,2,1].max{|a,b| b <=> a })
    assert_equal(%w[horse dog], ary.max(2))
    assert_equal(%w[albatross horse],
                 ary.max(2) {|a,b| a.length <=> b.length })
  end

  def test_minmax
    assert_equal([1, 3], @obj.minmax)
    assert_equal([3, 1], @obj.minmax {|a,b| b <=> a })
    ary = %w(albatross dog horse)
    assert_equal(["albatross", "horse"], ary.minmax)
    assert_equal(["dog", "albatross"], ary.minmax {|a,b| a.length <=> b.length })
    assert_equal([1, 3], [2,3,1].minmax)
    assert_equal([3, 1], [2,3,1].minmax {|a,b| b <=> a })
    assert_equal([1, 3], [2,2,3,3,1,1].minmax)
    assert_equal([nil, nil], [].minmax)
  end

  def test_min_by
    assert_equal(3, @obj.min_by {|x| -x })
    cond = ->(x, i) { -x }
    assert_equal([3, 2], @obj.each_with_index.min_by(&cond))
    a = %w(albatross dog horse)
    assert_equal("dog", a.min_by {|x| x.length })
    assert_equal(3, [2,3,1].min_by {|x| -x })
    assert_equal(%w[dog horse], a.min_by(2) {|x| x.length })
  end

  def test_max_by
    assert_equal(1, @obj.max_by {|x| -x })
    cond = ->(x, i) { -x }
    assert_equal([1, 0], @obj.each_with_index.max_by(&cond))
    a = %w(albatross dog horse)
    assert_equal("albatross", a.max_by {|x| x.length })
    assert_equal(1, [2,3,1].max_by {|x| -x })
    assert_equal(%w[albatross horse], a.max_by(2) {|x| x.length })
  end

  def test_minmax_by
    assert_equal([3, 1], @obj.minmax_by {|x| -x })
    cond = ->(x, i) { -x }
    assert_equal([[3, 2], [1, 0]], @obj.each_with_index.minmax_by(&cond))
    a = %w(albatross dog horse)
    assert_equal(["dog", "albatross"], a.minmax_by {|x| x.length })
    assert_equal([3, 1], [2,3,1].minmax_by {|x| -x })
  end

  def test_member
    assert(@obj.member?(1))
    assert(!(@obj.member?(4)))
    assert([1,2,3].member?(1))
    assert(!([1,2,3].member?(4)))
  end

  class Foo
    include Enumerable
    def each
      yield 1
      yield 1,2
    end
  end

  def test_each_with_index
    a = []
    @obj.each_with_index {|x, i| a << [x, i] }
    assert_equal([[1,0],[2,1],[3,2],[1,3],[2,4]], a)

    hash = Hash.new
    %w(cat dog wombat).each_with_index do |item, index|
      hash[item] = index
    end
    assert_equal({"cat"=>0, "wombat"=>2, "dog"=>1}, hash)
    assert_equal([[1, 0], [[1, 2], 1]], Foo.new.each_with_index.to_a)
  end

  def test_each_with_object
    obj = [0, 1]
    ret = (1..10).each_with_object(obj) {|i, memo|
      memo[0] += i
      memo[1] *= i
    }
    assert_same(obj, ret)
    assert_equal([55, 3628800], ret)
    assert_equal([[1, nil], [[1, 2], nil]], Foo.new.each_with_object(nil).to_a)
  end

  def test_each_entry
    assert_equal([1, 2, 3], [1, 2, 3].each_entry.to_a)
    assert_equal([1, [1, 2]], Foo.new.each_entry.to_a)
    a = []
    cond = ->(x, i) { a << x }
    @obj.each_with_index.each_entry(&cond)
    assert_equal([1, 2, 3, 1, 2], a)
  end

  def test_each_slice
    ary = []
    (1..10).each_slice(3) {|a| ary << a}
    assert_equal([[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]], ary)

    bug9749 = '[ruby-core:62060] [Bug #9749]'
    ary.clear
    (1..10).each_slice(3, &lambda {|a, *| ary << a})
    assert_equal([[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]], ary, bug9749)

    ary.clear
    (1..10).each_slice(10) {|a| ary << a}
    assert_equal([[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]], ary)

    ary.clear
    (1..10).each_slice(11) {|a| ary << a}
    assert_equal([[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]], ary)
  end

  def test_each_cons
    ary = []
    (1..5).each_cons(3) {|a| ary << a}
    assert_equal([[1, 2, 3], [2, 3, 4], [3, 4, 5]], ary)

    bug9749 = '[ruby-core:62060] [Bug #9749]'
    ary.clear
    (1..5).each_cons(3, &lambda {|a, *| ary << a})
    assert_equal([[1, 2, 3], [2, 3, 4], [3, 4, 5]], ary, bug9749)

    ary.clear
    (1..5).each_cons(5) {|a| ary << a}
    assert_equal([[1, 2, 3, 4, 5]], ary)

    ary.clear
    (1..5).each_cons(6) {|a| ary << a}
    assert_empty(ary)
  end

  def test_zip
    assert_equal([[1,1],[2,2],[3,3],[1,1],[2,2]], @obj.zip(@obj))
    a = []
    @obj.zip([:a, :b, :c]) {|x,y| a << [x, y] }
    assert_equal([[1,:a],[2,:b],[3,:c],[1,nil],[2,nil]], a)

    a = []
    cond = ->((x, i), y) { a << [x, y, i] }
    @obj.each_with_index.zip([:a, :b, :c], &cond)
    assert_equal([[1,:a,0],[2,:b,1],[3,:c,2],[1,nil,3],[2,nil,4]], a)

    a = []
    @obj.zip({a: "A", b: "B", c: "C"}) {|x,y| a << [x, y] }
    assert_equal([[1,[:a,"A"]],[2,[:b,"B"]],[3,[:c,"C"]],[1,nil],[2,nil]], a)

    ary = Object.new
    def ary.to_a;   [1, 2]; end
    assert_raise(TypeError) {%w(a b).zip(ary)}
    def ary.each; [3, 4].each{|e|yield e}; end
    assert_equal([[1, 3], [2, 4], [3, nil], [1, nil], [2, nil]], @obj.zip(ary))
    def ary.to_ary; [5, 6]; end
    assert_equal([[1, 5], [2, 6], [3, nil], [1, nil], [2, nil]], @obj.zip(ary))
  end

  def test_take
    assert_equal([1,2,3], @obj.take(3))
  end

  def test_take_while
    assert_equal([1,2], @obj.take_while {|x| x <= 2})
    cond = ->(x, i) {x <= 2}
    assert_equal([[1, 0], [2, 1]], @obj.each_with_index.take_while(&cond))

    bug5801 = '[ruby-dev:45040]'
    @empty.take_while {true}
    block = @empty.block
    assert_nothing_raised(bug5801) {100.times {block.call}}
  end

  def test_drop
    assert_equal([3,1,2], @obj.drop(2))
  end

  def test_drop_while
    assert_equal([3,1,2], @obj.drop_while {|x| x <= 2})
    cond = ->(x, i) {x <= 2}
    assert_equal([[3, 2], [1, 3], [2, 4]], @obj.each_with_index.drop_while(&cond))
  end

  def test_cycle
    assert_equal([1,2,3,1,2,1,2,3,1,2], @obj.cycle.take(10))
    a = []
    @obj.cycle(2) {|x| a << x}
    assert_equal([1,2,3,1,2,1,2,3,1,2], a)
    a = []
    cond = ->(x, i) {a << x}
    @obj.each_with_index.cycle(2, &cond)
    assert_equal([1,2,3,1,2,1,2,3,1,2], a)
  end

  def test_callcc
    assert_raise(RuntimeError) do
      c = nil
      @obj.sort_by {|x| callcc {|c2| c ||= c2 }; x }
      c.call
    end

    assert_raise(RuntimeError) do
      c = nil
      o = Object.new
      class << o; self; end.class_eval do
        define_method(:<=>) do |x|
          callcc {|c2| c ||= c2 }
          0
        end
      end
      [o, o].sort_by {|x| x }
      c.call
    end

    assert_raise(RuntimeError) do
      c = nil
      o = Object.new
      class << o; self; end.class_eval do
        define_method(:<=>) do |x|
          callcc {|c2| c ||= c2 }
          0
        end
      end
      [o, o, o].sort_by {|x| x }
      c.call
    end
  end

  def test_reverse_each
    assert_equal([2,1,3,2,1], @obj.reverse_each.to_a)
  end

  def test_chunk
    e = [].chunk {|elt| true }
    assert_equal([], e.to_a)

    e = @obj.chunk {|elt| elt & 2 == 0 ? false : true }
    assert_equal([[false, [1]], [true, [2, 3]], [false, [1]], [true, [2]]], e.to_a)

    e = @obj.chunk {|elt| elt < 3 ? :_alone : true }
    assert_equal([[:_alone, [1]],
                  [:_alone, [2]],
                  [true, [3]],
                  [:_alone, [1]],
                  [:_alone, [2]]], e.to_a)

    e = @obj.chunk {|elt| elt == 3 ? :_separator : true }
    assert_equal([[true, [1, 2]],
                  [true, [1, 2]]], e.to_a)

    e = @obj.chunk {|elt| elt == 3 ? nil : true }
    assert_equal([[true, [1, 2]],
                  [true, [1, 2]]], e.to_a)

    e = @obj.chunk {|elt| :_foo }
    assert_raise(RuntimeError) { e.to_a }
  end

  def test_slice_before
    e = [].slice_before {|elt| true }
    assert_equal([], e.to_a)

    e = @obj.slice_before {|elt| elt.even? }
    assert_equal([[1], [2,3,1], [2]], e.to_a)

    e = @obj.slice_before {|elt| elt.odd? }
    assert_equal([[1,2], [3], [1,2]], e.to_a)

    ss = %w[abc defg h ijk l mno pqr st u vw xy z]
    assert_equal([%w[abc defg h], %w[ijk l], %w[mno], %w[pqr st u vw xy z]],
                 ss.slice_before(/\A...\z/).to_a)
    assert_warning("") {ss.slice_before(/\A...\z/).to_a}
  end

  def test_slice_after0
    assert_raise(ArgumentError) { [].slice_after }
  end

  def test_slice_after1
    e = [].slice_after {|a| flunk "should not be called" }
    assert_equal([], e.to_a)

    e = [1,2].slice_after(1)
    assert_equal([[1], [2]], e.to_a)

    e = [1,2].slice_after(3)
    assert_equal([[1, 2]], e.to_a)

    [true, false].each {|b|
      block_results = [true, b]
      e = [1,2].slice_after {|a| block_results.shift }
      assert_equal([[1], [2]], e.to_a)
      assert_equal([], block_results)

      block_results = [false, b]
      e = [1,2].slice_after {|a| block_results.shift }
      assert_equal([[1, 2]], e.to_a)
      assert_equal([], block_results)
    }
  end

  def test_slice_after_both_pattern_and_block
    assert_raise(ArgumentError) { [].slice_after(1) {|a| true } }
  end

  def test_slice_after_continuation_lines
    lines = ["foo\n", "bar\\\n", "baz\n", "\n", "qux\n"]
    e = lines.slice_after(/[^\\]\n\z/)
    assert_equal([["foo\n"], ["bar\\\n", "baz\n"], ["\n", "qux\n"]], e.to_a)
  end

  def test_slice_before_empty_line
    lines = ["foo", "", "bar"]
    e = lines.slice_after(/\A\s*\z/)
    assert_equal([["foo", ""], ["bar"]], e.to_a)
  end

  def test_slice_when_0
    e = [].slice_when {|a, b| flunk "should not be called" }
    assert_equal([], e.to_a)
  end

  def test_slice_when_1
    e = [1].slice_when {|a, b| flunk "should not be called" }
    assert_equal([[1]], e.to_a)
  end

  def test_slice_when_2
    e = [1,2].slice_when {|a,b|
      assert_equal(1, a)
      assert_equal(2, b)
      true
    }
    assert_equal([[1], [2]], e.to_a)

    e = [1,2].slice_when {|a,b|
      assert_equal(1, a)
      assert_equal(2, b)
      false
    }
    assert_equal([[1, 2]], e.to_a)
  end

  def test_slice_when_3
    block_invocations = [
      lambda {|a, b|
        assert_equal(1, a)
        assert_equal(2, b)
        true
      },
      lambda {|a, b|
        assert_equal(2, a)
        assert_equal(3, b)
        false
      }
    ]
    e = [1,2,3].slice_when {|a,b|
      block_invocations.shift.call(a, b)
    }
    assert_equal([[1], [2, 3]], e.to_a)
    assert_equal([], block_invocations)
  end

  def test_slice_when_noblock
    assert_raise(ArgumentError) { [].slice_when }
  end

  def test_slice_when_contiguously_increasing_integers
    e = [1,4,9,10,11,12,15,16,19,20,21].slice_when {|i, j| i+1 != j }
    assert_equal([[1], [4], [9,10,11,12], [15,16], [19,20,21]], e.to_a)
  end

  def test_chunk_while_contiguously_increasing_integers
    e = [1,4,9,10,11,12,15,16,19,20,21].chunk_while {|i, j| i+1 == j }
    assert_equal([[1], [4], [9,10,11,12], [15,16], [19,20,21]], e.to_a)
  end

  def test_detect
    @obj = ('a'..'z')
    assert_equal('c', @obj.detect {|x| x == 'c' })

    proc = Proc.new {|x| x == 'c' }
    assert_equal('c', @obj.detect(&proc))

    lambda = ->(x) { x == 'c' }
    assert_equal('c', @obj.detect(&lambda))

    assert_equal(['c',2], @obj.each_with_index.detect {|x, i| x == 'c' })

    proc2 = Proc.new {|x, i| x == 'c' }
    assert_equal(['c',2], @obj.each_with_index.detect(&proc2))

    bug9605 = '[ruby-core:61340]'
    lambda2 = ->(x, i) { x == 'c' }
    assert_equal(['c',2], @obj.each_with_index.detect(&lambda2))
  end

  def test_select
    @obj = ('a'..'z')
    assert_equal(['c'], @obj.select {|x| x == 'c' })

    proc = Proc.new {|x| x == 'c' }
    assert_equal(['c'], @obj.select(&proc))

    lambda = ->(x) { x == 'c' }
    assert_equal(['c'], @obj.select(&lambda))

    assert_equal([['c',2]], @obj.each_with_index.select {|x, i| x == 'c' })

    proc2 = Proc.new {|x, i| x == 'c' }
    assert_equal([['c',2]], @obj.each_with_index.select(&proc2))

    bug9605 = '[ruby-core:61340]'
    lambda2 = ->(x, i) { x == 'c' }
    assert_equal([['c',2]], @obj.each_with_index.select(&lambda2))
  end

  def test_map
    @obj = ('a'..'e')
    assert_equal(['A', 'B', 'C', 'D', 'E'], @obj.map {|x| x.upcase })

    proc = Proc.new {|x| x.upcase }
    assert_equal(['A', 'B', 'C', 'D', 'E'], @obj.map(&proc))

    lambda = ->(x) { x.upcase }
    assert_equal(['A', 'B', 'C', 'D', 'E'], @obj.map(&lambda))

    assert_equal([['A',0], ['B',1], ['C',2], ['D',3], ['E',4]],
      @obj.each_with_index.map {|x, i| [x.upcase, i] })

    proc2 = Proc.new {|x, i| [x.upcase, i] }
    assert_equal([['A',0], ['B',1], ['C',2], ['D',3], ['E',4]],
      @obj.each_with_index.map(&proc2))

    lambda2 = ->(x, i) { [x.upcase, i] }
    assert_equal([['A',0], ['B',1], ['C',2], ['D',3], ['E',4]],
      @obj.each_with_index.map(&lambda2))
  end

  def test_flat_map
    @obj = [[1,2], [3,4]]
    assert_equal([2,4,6,8], @obj.flat_map {|i| i.map{|j| j*2} })

    proc = Proc.new {|i| i.map{|j| j*2} }
    assert_equal([2,4,6,8], @obj.flat_map(&proc))

    lambda = ->(i) { i.map{|j| j*2} }
    assert_equal([2,4,6,8], @obj.flat_map(&lambda))

    assert_equal([[1,2],0,[3,4],1],
                 @obj.each_with_index.flat_map {|x, i| [x,i] })

    proc2 = Proc.new {|x, i| [x,i] }
    assert_equal([[1,2],0,[3,4],1],
                 @obj.each_with_index.flat_map(&proc2))

    lambda2 = ->(x, i) { [x,i] }
    assert_equal([[1,2],0,[3,4],1],
                 @obj.each_with_index.flat_map(&lambda2))
  end
end
