# frozen_string_literal: false
require 'test/unit'

class TestEnumerator < Test::Unit::TestCase
  def setup
    @obj = Object.new
    class << @obj
      include Enumerable
      def foo(*a)
        a.each {|x| yield x }
      end
    end
    @sized = @obj.clone
    def @sized.size
      42
    end
  end

  def enum_test obj
    obj.map{|e|
      e
    }.sort
  end

  def test_iterators
    assert_equal [0, 1, 2], enum_test(3.times)
    assert_equal [:x, :y, :z], enum_test([:x, :y, :z].each)
    assert_equal [[:x, 1], [:y, 2]], enum_test({:x=>1, :y=>2}.each)
  end

  ## Enumerator as Iterator

  def test_next
    e = 3.times
    3.times{|i|
      assert_equal i, e.next
    }
    assert_raise(StopIteration){e.next}
  end

  def test_loop
    e = 3.times
    i = 0
    loop{
      assert_equal(i, e.next)
      i += 1
    }
  end

  def test_loop_return_value
    assert_equal nil, loop { break }
    assert_equal 42,  loop { break 42 }

    e = Enumerator.new { |y| y << 1; y << 2; :stopped }
    assert_equal :stopped, loop { e.next while true }
  end

  def test_nested_iteration
    def (o = Object.new).each
      yield :ok1
      yield [:ok2, :x].each.next
    end
    e = o.to_enum
    assert_equal :ok1, e.next
    assert_equal :ok2, e.next
    assert_raise(StopIteration){e.next}
  end


  def test_initialize
    assert_equal([1, 2, 3], @obj.to_enum(:foo, 1, 2, 3).to_a)
    _, err = capture_io do
      assert_equal([1, 2, 3], Enumerator.new(@obj, :foo, 1, 2, 3).to_a)
    end
    assert_equal([1, 2, 3], Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.take(3))
    assert_raise(ArgumentError) { Enumerator.new }

    enum = @obj.to_enum
    assert_raise(NoMethodError) { enum.each {} }
    enum.freeze
    assert_raise(FrozenError) {
      capture_io do
        # warning: Enumerator.new without a block is deprecated; use Object#to_enum
        enum.__send__(:initialize, @obj, :foo)
      end
    }
  end

  def test_initialize_copy
    assert_equal([1, 2, 3], @obj.to_enum(:foo, 1, 2, 3).dup.to_a)
    e = @obj.to_enum(:foo, 1, 2, 3)
    assert_nothing_raised { assert_equal(1, e.next) }
    assert_raise(TypeError) { e.dup }

    e = Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.dup
    assert_nothing_raised { assert_equal(1, e.next) }
    assert_raise(TypeError) { e.dup }
  end

  def test_gc
    assert_nothing_raised do
      1.times do
        foo = [1,2,3].to_enum
        GC.start
        foo
      end
      GC.start
    end
  end

  def test_slice
    assert_equal([[1,2,3],[4,5,6],[7,8,9],[10]], (1..10).each_slice(3).to_a)
  end

  def test_each_slice_size
    assert_equal(4, (1..10).each_slice(3).size)
    assert_equal(Float::INFINITY, 1.step.each_slice(3).size)
  end

  def test_cons
    a = [[1,2,3], [2,3,4], [3,4,5], [4,5,6], [5,6,7], [6,7,8], [7,8,9], [8,9,10]]
    assert_equal(a, (1..10).each_cons(3).to_a)
  end

  def test_with_index
    assert_equal([[1,0],[2,1],[3,2]], @obj.to_enum(:foo, 1, 2, 3).with_index.to_a)
    assert_equal([[1,5],[2,6],[3,7]], @obj.to_enum(:foo, 1, 2, 3).with_index(5).to_a)
  end

  def test_with_index_large_offset
    bug8010 = '[ruby-dev:47131] [Bug #8010]'
    s = 1 << (8*1.size-2)
    assert_equal([[1,s],[2,s+1],[3,s+2]], @obj.to_enum(:foo, 1, 2, 3).with_index(s).to_a, bug8010)
    s <<= 1
    assert_equal([[1,s],[2,s+1],[3,s+2]], @obj.to_enum(:foo, 1, 2, 3).with_index(s).to_a, bug8010)
  end

  def test_with_index_nonnum_offset
    bug8010 = '[ruby-dev:47131] [Bug #8010]'
    s = Object.new
    def s.to_int; 1 end
    assert_equal([[1,1],[2,2],[3,3]], @obj.to_enum(:foo, 1, 2, 3).with_index(s).to_a, bug8010)
  end

  def test_with_index_string_offset
    bug8010 = '[ruby-dev:47131] [Bug #8010]'
    assert_raise(TypeError, bug8010){ @obj.to_enum(:foo, 1, 2, 3).with_index('1').to_a }
  end

  def test_with_index_dangling_memo
    bug9178 = '[ruby-core:58692] [Bug #9178]'
    assert_separately([], <<-"end;")
    bug = "#{bug9178}"
    e = [1].to_enum(:chunk).with_index {|c,i| i == 5}
    assert_kind_of(Enumerator, e)
    assert_equal([false, [1]], e.to_a[0], bug)
    end;
  end

  def test_with_object
    obj = [0, 1]
    ret = (1..10).each.with_object(obj) {|i, memo|
      memo[0] += i
      memo[1] *= i
    }
    assert_same(obj, ret)
    assert_equal([55, 3628800], ret)

    a = [2,5,2,1,5,3,4,2,1,0]
    obj = {}
    ret = a.delete_if.with_object(obj) {|i, seen|
      if seen.key?(i)
        true
      else
        seen[i] = true
        false
      end
    }
    assert_same(obj, ret)
    assert_equal([2, 5, 1, 3, 4, 0], a)
  end

  def test_next_rewind
    e = @obj.to_enum(:foo, 1, 2, 3)
    assert_equal(1, e.next)
    assert_equal(2, e.next)
    e.rewind
    assert_equal(1, e.next)
    assert_equal(2, e.next)
    assert_equal(3, e.next)
    assert_raise(StopIteration) { e.next }
  end

  def test_peek
    a = [1]
    e = a.each
    assert_equal(1, e.peek)
    assert_equal(1, e.peek)
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.peek }
    assert_raise(StopIteration) { e.peek }
  end

  def test_peek_modify
    o = Object.new
    def o.each
      yield 1,2
    end
    e = o.to_enum
    a = e.peek
    a << 3
    assert_equal([1,2], e.peek)
  end

  def test_peek_values_modify
    o = Object.new
    def o.each
      yield 1,2
    end
    e = o.to_enum
    a = e.peek_values
    a << 3
    assert_equal([1,2], e.peek)
  end

  def test_next_after_stopiteration
    a = [1]
    e = a.each
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.next }
    assert_raise(StopIteration) { e.next }
    e.rewind
    assert_equal(1, e.next)
    assert_raise(StopIteration) { e.next }
    assert_raise(StopIteration) { e.next }
  end

  def test_stop_result
    a = [1]
    res = a.each {}
    e = a.each
    assert_equal(1, e.next)
    exc = assert_raise(StopIteration) { e.next }
    assert_equal(res, exc.result)
  end

  def test_next_values
    o = Object.new
    def o.each
      yield
      yield 1
      yield 1, 2
    end
    e = o.to_enum
    assert_equal(nil, e.next)
    assert_equal(1, e.next)
    assert_equal([1,2], e.next)
    e = o.to_enum
    assert_equal([], e.next_values)
    assert_equal([1], e.next_values)
    assert_equal([1,2], e.next_values)
  end

  def test_peek_values
    o = Object.new
    def o.each
      yield
      yield 1
      yield 1, 2
    end
    e = o.to_enum
    assert_equal(nil, e.peek)
    assert_equal(nil, e.next)
    assert_equal(1, e.peek)
    assert_equal(1, e.next)
    assert_equal([1,2], e.peek)
    assert_equal([1,2], e.next)
    e = o.to_enum
    assert_equal([], e.peek_values)
    assert_equal([], e.next_values)
    assert_equal([1], e.peek_values)
    assert_equal([1], e.next_values)
    assert_equal([1,2], e.peek_values)
    assert_equal([1,2], e.next_values)
    e = o.to_enum
    assert_equal([], e.peek_values)
    assert_equal(nil, e.next)
    assert_equal([1], e.peek_values)
    assert_equal(1, e.next)
    assert_equal([1,2], e.peek_values)
    assert_equal([1,2], e.next)
    e = o.to_enum
    assert_equal(nil, e.peek)
    assert_equal([], e.next_values)
    assert_equal(1, e.peek)
    assert_equal([1], e.next_values)
    assert_equal([1,2], e.peek)
    assert_equal([1,2], e.next_values)
  end

  def test_each_arg
    o = Object.new
    def o.each(ary)
      ary << 1
      yield
    end
    ary = []
    e = o.to_enum { 1 }
    assert_equal(1, e.size)
    e_arg = e.each(ary)
    assert_equal(nil, e_arg.size)
    e_arg.next
    assert_equal([1], ary)
  end

  def test_feed
    o = Object.new
    def o.each(ary)
      ary << yield
      ary << yield
      ary << yield
    end
    ary = []
    e = o.to_enum(:each, ary)
    e.next
    e.feed 1
    e.next
    e.feed 2
    e.next
    e.feed 3
    assert_raise(StopIteration) { e.next }
    assert_equal([1,2,3], ary)
  end

  def test_feed_mixed
    o = Object.new
    def o.each(ary)
      ary << yield
      ary << yield
      ary << yield
    end
    ary = []
    e = o.to_enum(:each, ary)
    e.next
    e.feed 1
    e.next
    e.next
    e.feed 3
    assert_raise(StopIteration) { e.next }
    assert_equal([1,nil,3], ary)
  end

  def test_feed_twice
    o = Object.new
    def o.each(ary)
      ary << yield
      ary << yield
      ary << yield
    end
    ary = []
    e = o.to_enum(:each, ary)
    e.feed 1
    assert_raise(TypeError) { e.feed 2 }
  end

  def test_feed_before_first_next
    o = Object.new
    def o.each(ary)
      ary << yield
      ary << yield
      ary << yield
    end
    ary = []
    e = o.to_enum(:each, ary)
    e.feed 1
    e.next
    e.next
    assert_equal([1], ary)
  end

  def test_rewind_clear_feed
    o = Object.new
    def o.each(ary)
      ary << yield
      ary << yield
      ary << yield
    end
    ary = []
    e = o.to_enum(:each, ary)
    e.next
    e.feed 1
    e.next
    e.feed 2
    e.rewind
    e.next
    e.next
    assert_equal([1,nil], ary)
  end

  def test_feed_yielder
    x = nil
    e = Enumerator.new {|y| x = y.yield; 10 }
    e.next
    e.feed 100
    exc = assert_raise(StopIteration) { e.next }
    assert_equal(100, x)
    assert_equal(10, exc.result)
  end

  def test_inspect
    e = (0..10).each_cons(2)
    assert_equal("#<Enumerator: 0..10:each_cons(2)>", e.inspect)

    e = (0..10).each_with_object({})
    assert_equal("#<Enumerator: 0..10:each_with_object({})>", e.inspect)

    e = (0..10).each_with_object(a: 1)
    assert_equal("#<Enumerator: 0..10:each_with_object(a: 1)>", e.inspect)

    e = Enumerator.new {|y| y.yield; 10 }
    assert_match(/\A#<Enumerator: .*:each>/, e.inspect)

    a = []
    e = a.each_with_object(a)
    a << e
    assert_equal("#<Enumerator: [#<Enumerator: ...>]:each_with_object([#<Enumerator: ...>])>",
		e.inspect)
  end

  def test_inspect_verbose
    bug6214 = '[ruby-dev:45449]'
    assert_warning("", bug6214) { "".bytes.inspect }
    assert_warning("", bug6214) { [].lazy.inspect }
  end

  def test_inspect_encoding
    c = Class.new{define_method("\u{3042}"){}}
    e = c.new.enum_for("\u{3042}")
    s = assert_nothing_raised(Encoding::CompatibilityError) {break e.inspect}
    assert_equal(Encoding::UTF_8, s.encoding)
    assert_match(/\A#<Enumerator: .*:\u{3042}>\z/, s)
  end

  def test_generator
    # note: Enumerator::Generator is a class just for internal
    g = Enumerator::Generator.new {|y| y << 1 << 2 << 3; :foo }
    g2 = g.dup
    a = []
    assert_equal(:foo, g.each {|x| a << x })
    assert_equal([1, 2, 3], a)
    a = []
    assert_equal(:foo, g2.each {|x| a << x })
    assert_equal([1, 2, 3], a)

    g.freeze
    assert_raise(FrozenError) {
      g.__send__ :initialize, proc { |y| y << 4 << 5 }
    }

    g = Enumerator::Generator.new(proc {|y| y << 4 << 5; :foo })
    a = []
    assert_equal(:foo, g.each {|x| a << x })
    assert_equal([4, 5], a)

    assert_raise(LocalJumpError) {Enumerator::Generator.new}
    assert_raise(TypeError) {Enumerator::Generator.new(1)}
    obj = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) {
      Enumerator::Generator.new(obj)
    }
  end

  def test_generator_args
    g = Enumerator::Generator.new {|y, x| y << 1 << 2 << 3; x }
    a = []
    assert_equal(:bar, g.each(:bar) {|x| a << x })
    assert_equal([1, 2, 3], a)
  end

  def test_yielder
    # note: Enumerator::Yielder is a class just for internal
    a = []
    y = Enumerator::Yielder.new {|x| a << x }
    assert_equal(y, y << 1 << 2 << 3)
    assert_equal([1, 2, 3], a)

    a = []
    y = Enumerator::Yielder.new {|x| a << x }
    assert_equal([1], y.yield(1))
    assert_equal([1, 2], y.yield(2))
    assert_equal([1, 2, 3], y.yield(3))
    assert_equal([1, 2, 3, 4], y.yield(4, 5))

    a = []
    y = Enumerator::Yielder.new {|*x| a.concat(x) }
    assert_equal([1], y.yield(1))
    assert_equal([1, 2, 3], y.yield(2, 3))

    assert_raise(LocalJumpError) { Enumerator::Yielder.new }

    # to_proc (explicit)
    a = []
    y = Enumerator::Yielder.new {|x| a << x }
    b = y.to_proc
    assert_kind_of(Proc, b)
    assert_equal([1], b.call(1))
    assert_equal([1], a)

    # to_proc (implicit)
    e = Enumerator.new { |y|
      assert_kind_of(Enumerator::Yielder, y)
      [1, 2, 3].each(&y)
    }
    assert_equal([1, 2, 3], e.to_a)
  end

  def test_size
    assert_equal nil, Enumerator.new{}.size
    assert_equal 42, Enumerator.new(->{42}){}.size
    obj = Object.new
    def obj.call; 42; end
    assert_equal 42, Enumerator.new(obj){}.size
    assert_equal 42, Enumerator.new(42){}.size
    assert_equal 1 << 70, Enumerator.new(1 << 70){}.size
    assert_equal Float::INFINITY, Enumerator.new(Float::INFINITY){}.size
    assert_equal nil, Enumerator.new(nil){}.size
    assert_raise(TypeError) { Enumerator.new("42"){} }

    assert_equal nil, @obj.to_enum(:foo, 0, 1).size
    assert_equal 2, @obj.to_enum(:foo, 0, 1){ 2 }.size
  end

  def test_size_for_enum_created_by_enumerators
    enum = to_enum{ 42 }
    assert_equal 42, enum.with_index.size
    assert_equal 42, enum.with_object(:foo).size
  end

  def test_size_for_enum_created_from_array
    arr = %w[hello world]
    %i[each each_with_index reverse_each sort_by! sort_by map map!
      keep_if reject! reject select! select filter! filter delete_if].each do |method|
      assert_equal arr.size, arr.send(method).size
    end
  end

  def test_size_for_enum_created_from_enumerable
    %i[find_all reject map flat_map partition group_by sort_by min_by max_by
      minmax_by each_with_index reverse_each each_entry filter_map].each do |method|
      assert_equal nil, @obj.send(method).size
      assert_equal 42, @sized.send(method).size
    end
    assert_equal nil, @obj.each_with_object(nil).size
    assert_equal 42, @sized.each_with_object(nil).size
  end

  def test_size_for_enum_created_from_hash
    h = {a: 1, b: 2, c: 3}
    methods = %i[delete_if reject reject! select select! filter filter! keep_if each each_key each_pair]
    enums = methods.map {|method| h.send(method)}
    s = enums.group_by(&:size)
    assert_equal([3], s.keys, ->{s.reject!{|k| k==3}.inspect})
    h[:d] = 4
    s = enums.group_by(&:size)
    assert_equal([4], s.keys, ->{s.reject!{|k| k==4}.inspect})
  end

  def test_size_for_enum_created_from_env
    %i[each_pair reject! delete_if select select! filter filter! keep_if].each do |method|
      assert_equal ENV.size, ENV.send(method).size
    end
  end

  def test_size_for_enum_created_from_struct
    s = Struct.new(:foo, :bar, :baz).new(1, 2)
    %i[each each_pair select].each do |method|
      assert_equal 3, s.send(method).size
    end
  end

  def check_consistency_for_combinatorics(method)
    [ [], [:a, :b, :c, :d, :e] ].product([-2, 0, 2, 5, 6]) do |array, arg|
      assert_equal array.send(method, arg).to_a.size, array.send(method, arg).size,
        "inconsistent size for #{array}.#{method}(#{arg})"
    end
  end

  def test_size_for_array_combinatorics
    check_consistency_for_combinatorics(:permutation)
    assert_equal 24, [0, 1, 2, 4].permutation.size
    assert_equal 2933197128679486453788761052665610240000000,
      (1..42).to_a.permutation(30).size # 1.upto(42).inject(:*) / 1.upto(12).inject(:*)

    check_consistency_for_combinatorics(:combination)
    assert_equal 28258808871162574166368460400,
      (1..100).to_a.combination(42).size
      # 1.upto(100).inject(:*) / 1.upto(42).inject(:*) / 1.upto(58).inject(:*)

    check_consistency_for_combinatorics(:repeated_permutation)
    assert_equal 291733167875766667063796853374976,
      (1..42).to_a.repeated_permutation(20).size # 42 ** 20

    check_consistency_for_combinatorics(:repeated_combination)
    assert_equal 28258808871162574166368460400,
      (1..59).to_a.repeated_combination(42).size
      # 1.upto(100).inject(:*) / 1.upto(42).inject(:*) / 1.upto(58).inject(:*)
  end

  def test_size_for_cycle
    assert_equal Float::INFINITY, [:foo].cycle.size
    assert_equal 10, [:foo, :bar].cycle(5).size
    assert_equal 0,  [:foo, :bar].cycle(-10).size
    assert_equal Float::INFINITY, {foo: 1}.cycle.size
    assert_equal 10, {foo: 1, bar: 2}.cycle(5).size
    assert_equal 0,  {foo: 1, bar: 2}.cycle(-10).size
    assert_equal 0,  [].cycle.size
    assert_equal 0,  [].cycle(5).size
    assert_equal 0,  {}.cycle.size
    assert_equal 0,  {}.cycle(5).size

    assert_equal nil, @obj.cycle.size
    assert_equal nil, @obj.cycle(5).size
    assert_equal Float::INFINITY, @sized.cycle.size
    assert_equal 126, @sized.cycle(3).size
    assert_equal Float::INFINITY, [].to_enum { 42 }.cycle.size
    assert_equal 0, [].to_enum { 0 }.cycle.size

    assert_raise(TypeError) {[].to_enum { 0 }.cycle("").size}
  end

  def test_size_for_loops
    assert_equal Float::INFINITY, loop.size
    assert_equal 42, 42.times.size
  end

  def test_size_for_each_slice
    assert_equal nil, @obj.each_slice(3).size
    assert_equal 6, @sized.each_slice(7).size
    assert_equal 5, @sized.each_slice(10).size
    assert_equal 1, @sized.each_slice(70).size
    assert_raise(ArgumentError){ @obj.each_slice(0).size }
  end

  def test_size_for_each_cons
    assert_equal nil, @obj.each_cons(3).size
    assert_equal 33, @sized.each_cons(10).size
    assert_equal 0, @sized.each_cons(70).size
    assert_raise(ArgumentError){ @obj.each_cons(0).size }
  end

  def test_size_for_step
    assert_equal 42, 5.step(46).size
    assert_equal 4, 1.step(10, 3).size
    assert_equal 3, 1.step(9, 3).size
    assert_equal 0, 1.step(-11).size
    assert_equal 0, 1.step(-11, 2).size
    assert_equal 7, 1.step(-11, -2).size
    assert_equal 7, 1.step(-11.1, -2).size
    assert_equal 0, 42.step(Float::INFINITY, -2).size
    assert_equal 1, 42.step(55, Float::INFINITY).size
    assert_equal 1, 42.step(Float::INFINITY, Float::INFINITY).size
    assert_equal 14, 0.1.step(4.2, 0.3).size
    assert_equal Float::INFINITY, 42.step(Float::INFINITY, 2).size

    assert_equal 10, (1..10).step.size
    assert_equal 4, (1..10).step(3).size
    assert_equal 3, (1...10).step(3).size
    assert_equal Float::INFINITY, (42..Float::INFINITY).step(2).size
    assert_equal 0, (1..10).step(-2).size
  end

  def test_size_for_downup_to
    assert_equal 0, 1.upto(-100).size
    assert_equal 102, 1.downto(-100).size
    assert_equal Float::INFINITY, 42.upto(Float::INFINITY).size
  end

  def test_size_for_string
    assert_equal 5, 'hello'.each_byte.size
    assert_equal 5, 'hello'.each_char.size
    assert_equal 5, 'hello'.each_codepoint.size
  end

  def test_peek_for_enumerator_objects
    e = 2.times
    assert_equal(0, e.peek)
    e.next
    assert_equal(1, e.peek)
    e.next
    assert_raise(StopIteration) { e.peek }
  end

  def test_uniq
    u = [0, 1, 0, 1].to_enum.lazy.uniq
    assert_equal([0, 1], u.force)
    assert_equal([0, 1], u.force)
  end

  def test_enum_chain_and_plus
    r = 1..5

    e1 = r.chain()
    assert_kind_of(Enumerator::Chain, e1)
    assert_equal(5, e1.size)
    ary = []
    e1.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5], ary)

    e2 = r.chain([6, 7, 8])
    assert_kind_of(Enumerator::Chain, e2)
    assert_equal(8, e2.size)
    ary = []
    e2.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8], ary)

    e3 = r.chain([6, 7], 8.step)
    assert_kind_of(Enumerator::Chain, e3)
    assert_equal(Float::INFINITY, e3.size)
    ary = []
    e3.take(10).each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], ary)

    # `a + b + c` should not return `Enumerator::Chain.new(a, b, c)`
    # because it is expected that `(a + b).each` be called.
    e4 = e2.dup
    class << e4
      attr_reader :each_is_called
      def each
        super
        @each_is_called = true
      end
    end
    e5 = e4 + 9.step
    assert_kind_of(Enumerator::Chain, e5)
    assert_equal(Float::INFINITY, e5.size)
    ary = []
    e5.take(10).each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], ary)
    assert_equal(true, e4.each_is_called)
  end

  def test_chained_enums
    a = (1..5).each

    e0 = Enumerator::Chain.new()
    assert_kind_of(Enumerator::Chain, e0)
    assert_equal(0, e0.size)
    ary = []
    e0.each { |x| ary << x }
    assert_equal([], ary)

    e1 = Enumerator::Chain.new(a)
    assert_kind_of(Enumerator::Chain, e1)
    assert_equal(5, e1.size)
    ary = []
    e1.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5], ary)

    e2 = Enumerator::Chain.new(a, [6, 7, 8])
    assert_kind_of(Enumerator::Chain, e2)
    assert_equal(8, e2.size)
    ary = []
    e2.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8], ary)

    e3 = Enumerator::Chain.new(a, [6, 7], 8.step)
    assert_kind_of(Enumerator::Chain, e3)
    assert_equal(Float::INFINITY, e3.size)
    ary = []
    e3.take(10).each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], ary)

    e4 = Enumerator::Chain.new(a, Enumerator.new { |y| y << 6 << 7 << 8 })
    assert_kind_of(Enumerator::Chain, e4)
    assert_equal(nil, e4.size)
    ary = []
    e4.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 6, 7, 8], ary)

    e5 = Enumerator::Chain.new(e1, e2)
    assert_kind_of(Enumerator::Chain, e5)
    assert_equal(13, e5.size)
    ary = []
    e5.each { |x| ary << x }
    assert_equal([1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 6, 7, 8], ary)

    rewound = []
    e1.define_singleton_method(:rewind) { rewound << object_id }
    e2.define_singleton_method(:rewind) { rewound << object_id }
    e5.rewind
    assert_equal(rewound, [e2.object_id, e1.object_id])

    rewound = []
    a = [1]
    e6 = Enumerator::Chain.new(a)
    a.define_singleton_method(:rewind) { rewound << object_id }
    e6.rewind
    assert_equal(rewound, [])

    assert_equal(
      '#<Enumerator::Chain: [' +
        '#<Enumerator::Chain: [' +
          '#<Enumerator: 1..5:each>' +
        ']>, ' +
        '#<Enumerator::Chain: [' +
          '#<Enumerator: 1..5:each>, ' +
          '[6, 7, 8]' +
        ']>' +
      ']>',
      e5.inspect
    )
  end

  def test_produce
    assert_raise(ArgumentError) { Enumerator.produce }

    # Without initial object
    passed_args = []
    enum = Enumerator.produce { |obj| passed_args << obj; (obj || 0).succ }
    assert_instance_of(Enumerator, enum)
    assert_equal Float::INFINITY, enum.size
    assert_equal [1, 2, 3], enum.take(3)
    assert_equal [nil, 1, 2], passed_args

    # With initial object
    passed_args = []
    enum = Enumerator.produce(1) { |obj| passed_args << obj; obj.succ }
    assert_instance_of(Enumerator, enum)
    assert_equal Float::INFINITY, enum.size
    assert_equal [1, 2, 3], enum.take(3)
    assert_equal [1, 2], passed_args

    # With initial keyword arguments
    passed_args = []
    enum = Enumerator.produce(a: 1, b: 1) { |obj| passed_args << obj; obj.shift if obj.respond_to?(:shift)}
    assert_instance_of(Enumerator, enum)
    assert_equal Float::INFINITY, enum.size
    assert_equal [{b: 1}, [1], :a, nil], enum.take(4)
    assert_equal [{b: 1}, [1], :a], passed_args

    # Raising StopIteration
    words = "The quick brown fox jumps over the lazy dog.".scan(/\w+/)
    enum = Enumerator.produce { words.shift or raise StopIteration }
    assert_equal Float::INFINITY, enum.size
    assert_instance_of(Enumerator, enum)
    assert_equal %w[The quick brown fox jumps over the lazy dog], enum.to_a

    # Raising StopIteration
    object = [[[["abc", "def"], "ghi", "jkl"], "mno", "pqr"], "stuv", "wxyz"]
    enum = Enumerator.produce(object) { |obj|
      obj.respond_to?(:first) or raise StopIteration
      obj.first
    }
    assert_equal Float::INFINITY, enum.size
    assert_instance_of(Enumerator, enum)
    assert_nothing_raised {
      assert_equal [
        [[[["abc", "def"], "ghi", "jkl"], "mno", "pqr"], "stuv", "wxyz"],
        [[["abc", "def"], "ghi", "jkl"], "mno", "pqr"],
        [["abc", "def"], "ghi", "jkl"],
        ["abc", "def"],
        "abc",
      ], enum.to_a
    }
  end

  def test_chain_each_lambda
    c = Class.new do
      include Enumerable
      attr_reader :is_lambda
      def each(&block)
        return to_enum unless block
        @is_lambda = block.lambda?
      end
    end
    e = c.new
    e.chain.each{}
    assert_equal(false, e.is_lambda)
    e.chain.each(&->{})
    assert_equal(true, e.is_lambda)
  end
end
