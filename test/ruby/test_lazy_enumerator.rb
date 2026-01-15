# frozen_string_literal: false
require 'test/unit'

class TestLazyEnumerator < Test::Unit::TestCase
  class Step
    include Enumerable
    attr_reader :current, :args

    def initialize(enum)
      @enum = enum
      @current = nil
      @args = nil
    end

    def each(*args)
      @args = args
      @enum.each do |v|
        @current = v
        if v.is_a? Enumerable
          yield(*v)
        else
          yield(v)
        end
      end
    end
  end

  def test_initialize
    assert_equal([1, 2, 3], [1, 2, 3].lazy.to_a)
    assert_equal([1, 2, 3], Enumerator::Lazy.new([1, 2, 3]){|y, v| y << v}.to_a)
    assert_raise(ArgumentError) { Enumerator::Lazy.new([1, 2, 3]) }

    a = [1, 2, 3].lazy
    a.freeze
    assert_raise(FrozenError) {
      a.__send__ :initialize, [4, 5], &->(y, *v) { y << yield(*v) }
    }
  end

  def test_each_args
    a = Step.new(1..3)
    assert_equal(1, a.lazy.each(4).first)
    assert_equal([4], a.args)
  end

  def test_each_line
    name = lineno = nil
    File.open(__FILE__) do |f|
      f.each("").map do |paragraph|
        paragraph[/\A\s*(.*)/, 1]
      end.find do |line|
        if name = line[/^class\s+(\S+)/, 1]
          lineno = f.lineno
          true
        end
      end
    end
    assert_equal(self.class.name, name)
    assert_operator(lineno, :>, 2)

    name = lineno = nil
    File.open(__FILE__) do |f|
      f.lazy.each("").map do |paragraph|
        paragraph[/\A\s*(.*)/, 1]
      end.find do |line|
        if name = line[/^class\s+(\S+)/, 1]
          lineno = f.lineno
          true
        end
      end
    end
    assert_equal(self.class.name, name)
    assert_equal(2, lineno)
  end

  def test_select
    a = Step.new(1..6)
    assert_equal(4, a.select {|x| x > 3}.first)
    assert_equal(6, a.current)
    assert_equal(4, a.lazy.select {|x| x > 3}.first)
    assert_equal(4, a.current)

    a = Step.new(['word', nil, 1])
    assert_raise(TypeError) {a.select {|x| "x"+x}.first}
    assert_equal(nil, a.current)
    assert_equal("word", a.lazy.select {|x| "x"+x}.first)
    assert_equal("word", a.current)
  end

  def test_select_multiple_values
    e = Enumerator.new { |yielder|
      for i in 1..5
        yielder.yield(i, i.to_s)
      end
    }
    assert_equal([[2, "2"], [4, "4"]],
                 e.select {|x| x[0] % 2 == 0})
    assert_equal([[2, "2"], [4, "4"]],
                 e.lazy.select {|x| x[0] % 2 == 0}.force)
  end

  def test_map
    a = Step.new(1..3)
    assert_equal(2, a.map {|x| x * 2}.first)
    assert_equal(3, a.current)
    assert_equal(2, a.lazy.map {|x| x * 2}.first)
    assert_equal(1, a.current)
  end

  def test_map_packed_nested
    bug = '[ruby-core:81638] [Bug#13648]'

    a = Step.new([[1, 2]])
    expected = [[[1, 2]]]
    assert_equal(expected, a.map {|*args| args}.map {|*args| args}.to_a)
    assert_equal(expected, a.lazy.map {|*args| args}.map {|*args| args}.to_a, bug)
  end

  def test_flat_map
    a = Step.new(1..3)
    assert_equal(2, a.flat_map {|x| [x * 2]}.first)
    assert_equal(3, a.current)
    assert_equal(2, a.lazy.flat_map {|x| [x * 2]}.first)
    assert_equal(1, a.current)
  end

  def test_flat_map_nested
    a = Step.new(1..3)
    assert_equal([1, "a"],
                 a.flat_map {|x| ("a".."c").map {|y| [x, y]}}.first)
    assert_equal(3, a.current)
    assert_equal([1, "a"],
                 a.lazy.flat_map {|x| ("a".."c").lazy.map {|y| [x, y]}}.first)
    assert_equal(1, a.current)
  end

  def test_flat_map_to_ary
    to_ary = Class.new {
      def initialize(value)
        @value = value
      end

      def to_ary
        [:to_ary, @value]
      end
    }
    assert_equal([:to_ary, 1, :to_ary, 2, :to_ary, 3],
                 [1, 2, 3].flat_map {|x| to_ary.new(x)})
    assert_equal([:to_ary, 1, :to_ary, 2, :to_ary, 3],
                 [1, 2, 3].lazy.flat_map {|x| to_ary.new(x)}.force)
  end

  def test_flat_map_non_array
    assert_equal(["1", "2", "3"], [1, 2, 3].flat_map {|x| x.to_s})
    assert_equal(["1", "2", "3"], [1, 2, 3].lazy.flat_map {|x| x.to_s}.force)
  end

  def test_flat_map_hash
    assert_equal([{?a=>97}, {?b=>98}, {?c=>99}], [?a, ?b, ?c].flat_map {|x| {x=>x.ord}})
    assert_equal([{?a=>97}, {?b=>98}, {?c=>99}], [?a, ?b, ?c].lazy.flat_map {|x| {x=>x.ord}}.force)
  end

  def test_flat_map_take
    assert_equal([1,2]*3, [[1,2]].cycle.lazy.take(3).flat_map {|x| x}.to_a)
  end

  def test_reject
    a = Step.new(1..6)
    assert_equal(4, a.reject {|x| x < 4}.first)
    assert_equal(6, a.current)
    assert_equal(4, a.lazy.reject {|x| x < 4}.first)
    assert_equal(4, a.current)

    a = Step.new(['word', nil, 1])
    assert_equal(nil, a.reject {|x| x}.first)
    assert_equal(1, a.current)
    assert_equal(nil, a.lazy.reject {|x| x}.first)
    assert_equal(nil, a.current)
  end

  def test_reject_multiple_values
    e = Enumerator.new { |yielder|
      for i in 1..5
        yielder.yield(i, i.to_s)
      end
    }
    assert_equal([[2, "2"], [4, "4"]],
                 e.reject {|x| x[0] % 2 != 0})
    assert_equal([[2, "2"], [4, "4"]],
                 e.lazy.reject {|x| x[0] % 2 != 0}.force)
  end

  def test_grep
    a = Step.new('a'..'f')
    assert_equal('c', a.grep(/c/).first)
    assert_equal('f', a.current)
    assert_equal('c', a.lazy.grep(/c/).first)
    assert_equal('c', a.current)
    assert_equal(%w[a e], a.grep(proc {|x| /[aeiou]/ =~ x}))
    assert_equal(%w[a e], a.lazy.grep(proc {|x| /[aeiou]/ =~ x}).to_a)
  end

  def test_grep_with_block
    a = Step.new('a'..'f')
    assert_equal('C', a.grep(/c/) {|i| i.upcase}.first)
    assert_equal('C', a.lazy.grep(/c/) {|i| i.upcase}.first)
  end

  def test_grep_multiple_values
    e = Enumerator.new { |yielder|
      3.times { |i|
        yielder.yield(i, i.to_s)
      }
    }
    assert_equal([[2, "2"]], e.grep(proc {|x| x == [2, "2"]}))
    assert_equal([[2, "2"]], e.lazy.grep(proc {|x| x == [2, "2"]}).force)
    assert_equal(["22"],
                 e.lazy.grep(proc {|x| x == [2, "2"]}, &:join).force)
  end

  def test_grep_v
    a = Step.new('a'..'f')
    assert_equal('b', a.grep_v(/a/).first)
    assert_equal('f', a.current)
    assert_equal('a', a.lazy.grep_v(/c/).first)
    assert_equal('a', a.current)
    assert_equal(%w[b c d f], a.grep_v(proc {|x| /[aeiou]/ =~ x}))
    assert_equal(%w[b c d f], a.lazy.grep_v(proc {|x| /[aeiou]/ =~ x}).to_a)
  end

  def test_grep_v_with_block
    a = Step.new('a'..'f')
    assert_equal('B', a.grep_v(/a/) {|i| i.upcase}.first)
    assert_equal('B', a.lazy.grep_v(/a/) {|i| i.upcase}.first)
  end

  def test_grep_v_multiple_values
    e = Enumerator.new { |yielder|
      3.times { |i|
        yielder.yield(i, i.to_s)
      }
    }
    assert_equal([[0, "0"], [1, "1"]], e.grep_v(proc {|x| x == [2, "2"]}))
    assert_equal([[0, "0"], [1, "1"]], e.lazy.grep_v(proc {|x| x == [2, "2"]}).force)
    assert_equal(["00", "11"],
                 e.lazy.grep_v(proc {|x| x == [2, "2"]}, &:join).force)
  end

  def test_zip
    a = Step.new(1..3)
    assert_equal([1, "a"], a.zip("a".."c").first)
    assert_equal(3, a.current)
    assert_equal([1, "a"], a.lazy.zip("a".."c").first)
    assert_equal(1, a.current)
  end

  def test_zip_short_arg
    a = Step.new(1..5)
    assert_equal([5, nil], a.zip("a".."c").last)
    assert_equal([5, nil], a.lazy.zip("a".."c").force.last)
  end

  def test_zip_without_arg
    a = Step.new(1..3)
    assert_equal([1], a.zip.first)
    assert_equal(3, a.current)
    assert_equal([1], a.lazy.zip.first)
    assert_equal(1, a.current)
  end

  def test_zip_bad_arg
    a = Step.new(1..3)
    assert_raise(TypeError){ a.lazy.zip(42) }
  end

  def test_zip_with_block
    # zip should be eager when a block is given
    a = Step.new(1..3)
    ary = []
    assert_equal(nil, a.lazy.zip("a".."c") {|x, y| ary << [x, y]})
    assert_equal(a.zip("a".."c"), ary)
    assert_equal(3, a.current)
  end

  def test_zip_map_lambda_bug_19569
    ary = [1, 2, 3].to_enum.lazy.zip([:a, :b, :c]).map(&:last).to_a
    assert_equal([:a, :b, :c], ary)
  end

  def test_take
    a = Step.new(1..10)
    assert_equal(1, a.take(5).first)
    assert_equal(5, a.current)
    assert_equal(1, a.lazy.take(5).first)
    assert_equal(1, a.current)
    assert_equal((1..5).to_a, a.lazy.take(5).force)
    assert_equal(5, a.current)
    a = Step.new(1..10)
    assert_equal([], a.lazy.take(0).force)
    assert_equal(nil, a.current)
  end

  def test_take_0_bug_18971
    def (bomb = Object.new.extend(Enumerable)).each
      raise
    end
    [2..10, bomb].each do |e|
      assert_equal([], e.lazy.take(0).map(&:itself).to_a)
      assert_equal([], e.lazy.take(0).select(&:even?).to_a)
      assert_equal([], e.lazy.take(0).select(&:odd?).to_a)
      assert_equal([], e.lazy.take(0).reject(&:even?).to_a)
      assert_equal([], e.lazy.take(0).reject(&:odd?).to_a)
      assert_equal([], e.lazy.take(0).take(1).to_a)
      assert_equal([], e.lazy.take(0).take(0).take(1).to_a)
      assert_equal([], e.lazy.take(0).drop(0).to_a)
      assert_equal([], e.lazy.take(0).find_all {|_| true}.to_a)
      assert_equal([], e.lazy.take(0).zip((12..20)).to_a)
      assert_equal([], e.lazy.take(0).uniq.to_a)
      assert_equal([], e.lazy.take(0).sort.to_a)
    end
  end

  def test_take_bad_arg
    a = Step.new(1..10)
    assert_raise(ArgumentError) { a.lazy.take(-1) }
  end

  def test_take_recycle
    bug6428 = '[ruby-dev:45634]'
    a = Step.new(1..10)
    take5 = a.lazy.take(5)
    assert_equal((1..5).to_a, take5.force, bug6428)
    assert_equal((1..5).to_a, take5.force, bug6428)
  end

  def test_take_nested
    bug7696 = '[ruby-core:51470]'
    a = Step.new(1..10)
    take5 = a.lazy.take(5)
    assert_equal([*(1..5)]*5, take5.flat_map{take5}.force, bug7696)
  end

  def test_drop_while_nested
    bug7696 = '[ruby-core:51470]'
    a = Step.new(1..10)
    drop5 = a.lazy.drop_while{|x| x < 6}
    assert_equal([*(6..10)]*5, drop5.flat_map{drop5}.force, bug7696)
  end

  def test_drop_nested
    bug7696 = '[ruby-core:51470]'
    a = Step.new(1..10)
    drop5 = a.lazy.drop(5)
    assert_equal([*(6..10)]*5, drop5.flat_map{drop5}.force, bug7696)
  end

  def test_zip_nested
    bug7696 = '[ruby-core:51470]'
    enum = ('a'..'z').each
    enum.next
    zip = (1..3).lazy.zip(enum, enum)
    assert_equal([[1, 'a', 'a'], [2, 'b', 'b'], [3, 'c', 'c']]*3, zip.flat_map{zip}.force, bug7696)
  end

  def test_zip_lazy_on_args
    zip = Step.new(1..2).lazy.zip(42..Float::INFINITY)
    assert_equal [[1, 42], [2, 43]], zip.force
  end

  def test_zip_efficient_on_array_args
    ary = [42, :foo]
    %i[to_enum enum_for lazy each].each do |forbid|
      ary.define_singleton_method(forbid){ fail "#{forbid} was called"}
    end
    zip = Step.new(1..2).lazy.zip(ary)
    assert_equal [[1, 42], [2, :foo]], zip.force
  end

  def test_zip_nonsingle
    bug8735 = '[ruby-core:56383] [Bug #8735]'

    obj = Object.new
    def obj.each
      yield
      yield 1, 2
    end

    assert_equal(obj.to_enum.zip(obj.to_enum), obj.to_enum.lazy.zip(obj.to_enum).force, bug8735)
  end

  def test_take_rewound
    bug7696 = '[ruby-core:51470]'
    e=(1..42).lazy.take(2)
    assert_equal 1, e.next, bug7696
    assert_equal 2, e.next, bug7696
    e.rewind
    assert_equal 1, e.next, bug7696
    assert_equal 2, e.next, bug7696
  end

  def test_take_while
    a = Step.new(1..10)
    assert_equal(1, a.take_while {|i| i < 5}.first)
    assert_equal(5, a.current)
    assert_equal(1, a.lazy.take_while {|i| i < 5}.first)
    assert_equal(1, a.current)
    assert_equal((1..4).to_a, a.lazy.take_while {|i| i < 5}.to_a)
  end

  def test_drop
    a = Step.new(1..10)
    assert_equal(6, a.drop(5).first)
    assert_equal(10, a.current)
    assert_equal(6, a.lazy.drop(5).first)
    assert_equal(6, a.current)
    assert_equal((6..10).to_a, a.lazy.drop(5).to_a)
  end

  def test_drop_while
    a = Step.new(1..10)
    assert_equal(5, a.drop_while {|i| i % 5 > 0}.first)
    assert_equal(10, a.current)
    assert_equal(5, a.lazy.drop_while {|i| i % 5 > 0}.first)
    assert_equal(5, a.current)
    assert_equal((5..10).to_a, a.lazy.drop_while {|i| i % 5 > 0}.to_a)
  end

  def test_drop_and_take
    assert_equal([4, 5], (1..Float::INFINITY).lazy.drop(3).take(2).to_a)
  end

  def test_cycle
    a = Step.new(1..3)
    assert_equal("1", a.cycle(2).map(&:to_s).first)
    assert_equal(3, a.current)
    assert_equal("1", a.lazy.cycle(2).map(&:to_s).first)
    assert_equal(1, a.current)
  end

  def test_cycle_with_block
    # cycle should be eager when a block is given
    a = Step.new(1..3)
    ary = []
    assert_equal(nil, a.lazy.cycle(2) {|i| ary << i})
    assert_equal(a.cycle(2).to_a, ary)
    assert_equal(3, a.current)
  end

  def test_cycle_chain
    a = 1..3
    assert_equal([1,2,3,1,2,3,1,2,3,1], a.lazy.cycle.take(10).force)
    assert_equal([2,2,2,2,2,2,2,2,2,2], a.lazy.cycle.select {|x| x == 2}.take(10).force)
    assert_equal([2,2,2,2,2,2,2,2,2,2], a.lazy.select {|x| x == 2}.cycle.take(10).force)
  end

  def test_force
    assert_equal([1, 2, 3], (1..Float::INFINITY).lazy.take(3).force)
  end

  def test_inspect
    assert_equal("#<Enumerator::Lazy: 1..10>", (1..10).lazy.inspect)
    assert_equal('#<Enumerator::Lazy: #<Enumerator: "foo":each_char>>',
                 "foo".each_char.lazy.inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:map>",
                 (1..10).lazy.map {}.inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:take(0)>",
                 (1..10).lazy.take(0).inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:take(3)>",
                 (1..10).lazy.take(3).inspect)
    assert_equal('#<Enumerator::Lazy: #<Enumerator::Lazy: "a".."c">:grep(/b/)>',
                 ("a".."c").lazy.grep(/b/).inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:cycle(3)>",
                 (1..10).lazy.cycle(3).inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:cycle>",
                 (1..10).lazy.cycle.inspect)
    assert_equal("#<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:cycle(3)>",
                 (1..10).lazy.cycle(3).inspect)
    l = (1..10).lazy.map {}.collect {}.flat_map {}.collect_concat {}.select {}.find_all {}.reject {}.grep(1).zip(?a..?c).take(10).take_while {}.drop(3).drop_while {}.cycle(3)
    assert_equal(<<EOS.chomp, l.inspect)
#<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: 1..10>:map>:collect>:flat_map>:collect_concat>:select>:find_all>:reject>:grep(1)>:zip("a".."c")>:take(10)>:take_while>:drop(3)>:drop_while>:cycle(3)>
EOS
  end

  def test_lazy_eager
    lazy = [1, 2, 3].lazy.map { |x| x * 2 }
    enum = lazy.eager
    assert_equal Enumerator, enum.class
    assert_equal 3, enum.size
    assert_equal [1, 2, 3], enum.map { |x| x / 2 }
  end

  def test_lazy_zip_map_yield_arity_bug_20623
    assert_equal([[1, 2]], [1].lazy.zip([2].lazy).map { |x| x }.force)
  end

  def test_lazy_to_enum
    lazy = [1, 2, 3].lazy
    def lazy.foo(*args)
      yield args
      yield args
    end
    enum = lazy.to_enum(:foo, :hello, :world)
    assert_equal Enumerator::Lazy, enum.class
    assert_equal nil, enum.size
    assert_equal [[:hello, :world], [:hello, :world]], enum.to_a

    assert_equal [1, 2, 3], lazy.to_enum.to_a
  end

  def test_lazy_to_enum_lazy_methods
    a = [1, 2, 3].to_enum
    pr = proc{|x| [x, x * 2]}
    selector = proc{|x| x*2 if x % 2 == 0}

    [
      [:with_index, nil],
      [:with_index, 10, nil],
      [:with_index, 10, pr],
      [:map, nil],
      [:map, pr],
      [:collect, nil],
      [:flat_map, nil],
      [:flat_map, pr],
      [:collect_concat, nil],
      [:select, nil],
      [:select, selector],
      [:find_all, nil],
      [:filter, nil],
      [:filter_map, selector],
      [:filter_map, nil],
      [:reject, selector],
      [:grep, selector, nil],
      [:grep, selector, pr],
      [:grep_v, selector, nil],
      [:grep_v, selector, pr],
      [:zip, a, nil],
      [:take, 3, nil],
      [:take_while, nil],
      [:take_while, selector],
      [:drop, 1, nil],
      [:drop_while, nil],
      [:drop_while, selector],
      [:uniq, nil],
      [:uniq, proc{|x| x.odd?}],
    ].each do |args|
      block = args.pop
      assert_equal [1, 2, 3].to_enum.to_enum(*args).first(2).to_a, [1, 2, 3].to_enum.lazy.to_enum(*args).first(2).to_a
      assert_equal (0..50).to_enum.to_enum(*args).first(2).to_a, (0..50000).to_enum.lazy.to_enum(*args).first(2).to_a
      if block
        assert_equal [1, 2, 3, 4].to_enum.to_enum(*args).map(&block).first(2).to_a, [1, 2, 3, 4].to_enum.lazy.to_enum(*args).map(&block).first(2).to_a
        unless args.first == :take_while || args.first == :drop_while
          assert_equal (0..50).to_enum.to_enum(*args).map(&block).first(2).to_a, (0..50000).to_enum.lazy.to_enum(*args).map(&block).first(2).to_a
        end
      end
    end
  end

  def test_size
    lazy = [1, 2, 3].lazy
    assert_equal 3, lazy.size
    assert_equal 42, Enumerator::Lazy.new([],->{42}){}.size
    assert_equal 42, Enumerator::Lazy.new([],42){}.size
    assert_equal 42, Enumerator::Lazy.new([],42){}.lazy.size
    assert_equal 42, lazy.to_enum{ 42 }.size

    %i[map collect].each do |m|
      assert_equal 3, lazy.send(m){}.size
    end
    assert_equal 3, lazy.zip([4]).size
    %i[flat_map collect_concat select find_all reject take_while drop_while].each do |m|
      assert_equal nil, lazy.send(m){}.size
    end
    assert_equal nil, lazy.grep(//).size

    assert_equal 2, lazy.take(2).size
    assert_equal 3, lazy.take(4).size
    assert_equal 4, loop.lazy.take(4).size
    assert_equal nil, lazy.select{}.take(4).size

    assert_equal 1, lazy.drop(2).size
    assert_equal 0, lazy.drop(4).size
    assert_equal Float::INFINITY, loop.lazy.drop(4).size
    assert_equal nil, lazy.select{}.drop(4).size

    assert_equal 0, lazy.cycle(0).size
    assert_equal 6, lazy.cycle(2).size
    assert_equal 3 << 80, 4.times.inject(lazy){|enum| enum.cycle(1 << 20)}.size
    assert_equal Float::INFINITY, lazy.cycle.size
    assert_equal Float::INFINITY, loop.lazy.cycle(4).size
    assert_equal Float::INFINITY, loop.lazy.cycle.size
    assert_equal nil, lazy.select{}.cycle(4).size
    assert_equal nil, lazy.select{}.cycle.size

    class << (obj = Object.new)
      def each; end
      def size; 0; end
      include Enumerable
    end
    lazy = obj.lazy
    assert_equal 0, lazy.cycle.size
    assert_raise(TypeError) {lazy.cycle("").size}
  end

  def test_map_zip
    bug7507 = '[ruby-core:50545]'
    assert_ruby_status(["-e", "GC.stress = true", "-e", "(1..10).lazy.map{}.zip(){}"], "", bug7507)
    assert_ruby_status(["-e", "GC.stress = true", "-e", "(1..10).lazy.map{}.zip().to_a"], "", bug7507)
  end

  def test_require_block
    %i[select reject drop_while take_while map flat_map].each do |method|
      assert_raise(ArgumentError){ [].lazy.send(method) }
    end
  end

  def test_laziness_conservation
    bug7507 = '[ruby-core:51510]'
    {
      slice_before: //,
      slice_after: //,
      with_index: nil,
      cycle: nil,
      each_with_object: 42,
      each_slice: 42,
      each_entry: nil,
      each_cons: 42,
    }.each do |method, arg|
      assert_equal Enumerator::Lazy, [].lazy.send(method, *arg).class, bug7507
    end
    assert_equal Enumerator::Lazy, [].lazy.chunk{}.class, bug7507
    assert_equal Enumerator::Lazy, [].lazy.slice_when{}.class, bug7507
  end

  def test_each_cons_limit
    n = 1 << 120
    assert_equal([1, 2], (1..n).lazy.each_cons(2).first)
    assert_equal([[1, 2], [2, 3]], (1..n).lazy.each_cons(2).first(2))
  end

  def test_each_slice_limit
    n = 1 << 120
    assert_equal([1, 2], (1..n).lazy.each_slice(2).first)
    assert_equal([[1, 2], [3, 4]], (1..n).lazy.each_slice(2).first(2))
  end

  def test_no_warnings
    le = (1..3).lazy
    assert_warning("") {le.zip([4,5,6]).force}
    assert_warning("") {le.zip(4..6).force}
    assert_warning("") {le.take(1).force}
    assert_warning("") {le.drop(1).force}
    assert_warning("") {le.drop_while{false}.force}
  end

  def test_symbol_chain
    assert_equal(["1", "3"], [1, 2, 3].lazy.reject(&:even?).map(&:to_s).force)
    assert_raise(NoMethodError) do
      [1, 2, 3].lazy.map(&:undefined).map(&:to_s).force
    end
  end

  def test_uniq
    u = (1..Float::INFINITY).lazy.uniq do |x|
      raise "too big" if x > 10000
      (x**2) % 10
    end
    assert_equal([1, 2, 3, 4, 5, 10], u.first(6))
    assert_equal([1, 2, 3, 4, 5, 10], u.first(6))
  end

  def test_filter_map
    e = (1..Float::INFINITY).lazy.filter_map do |x|
      raise "too big" if x > 10000
      (x**2) % 10 if x.even?
    end
    assert_equal([4, 6, 6, 4, 0, 4], e.first(6))
    assert_equal([4, 6, 6, 4, 0, 4], e.first(6))
  end

  def test_with_index
    feature7877 = '[ruby-dev:47025] [Feature #7877]'
    leibniz = ->(n) {
      (0..Float::INFINITY).lazy.with_index.map {|i, j|
        raise IndexError, "limit exceeded (#{n})" unless j < n
        ((-1) ** j) / (2*i+1).to_f
      }.take(n).reduce(:+)
    }
    assert_nothing_raised(IndexError, feature7877) {
      assert_in_epsilon(Math::PI/4, leibniz[1000])
    }

    a = []
    ary = (0..Float::INFINITY).lazy.with_index(2) {|i, j| a << [i-1, j] }.take(2).to_a
    assert_equal([[-1, 2], [0, 3]], a)
    assert_equal([0, 1], ary)

    a = []
    ary = (0..Float::INFINITY).lazy.with_index(2, &->(i,j) { a << [i-1, j] }).take(2).to_a
    assert_equal([[-1, 2], [0, 3]], a)
    assert_equal([0, 1], ary)

    ary = (0..Float::INFINITY).lazy.with_index(2).map {|i, j| [i-1, j] }.take(2).to_a
    assert_equal([[-1, 2], [0, 3]], ary)

    ary = (0..Float::INFINITY).lazy.with_index(2).map(&->(i, j) { [i-1, j] }).take(2).to_a
    assert_equal([[-1, 2], [0, 3]], ary)

    ary = (0..Float::INFINITY).lazy.with_index(2).take(2).to_a
    assert_equal([[0, 2], [1, 3]], ary)

    ary = (0..Float::INFINITY).lazy.with_index.take(2).to_a
    assert_equal([[0, 0], [1, 1]], ary)
  end

  def test_with_index_size
    assert_equal(3, Enumerator::Lazy.new([1, 2, 3], 3){|y, v| y << v}.with_index.size)
  end
end
