require 'test/unit'
require_relative 'envutil'

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
    assert_equal [[:x, 1], [:y, 2]], enum_test({:x=>1, :y=>2})
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
    assert_match 'Enumerator.new without a block is deprecated', err
    assert_equal([1, 2, 3], Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.take(3))
    assert_raise(ArgumentError) { Enumerator.new }

    enum = @obj.to_enum
    assert_raise(NoMethodError) { enum.each {} }
    enum.freeze
    assert_raise(RuntimeError) {
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
      end
      GC.start
    end
  end

  def test_slice
    assert_equal([[1,2,3],[4,5,6],[7,8,9],[10]], (1..10).each_slice(3).to_a)
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
    e = o.to_enum.each(ary)
    e.next
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
    assert_raise(RuntimeError) {
      g.__send__ :initialize, proc { |y| y << 4 << 5 }
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

    assert_raise(LocalJumpError) { Enumerator::Yielder.new }
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
      keep_if reject! reject select! select delete_if].each do |method|
      assert_equal arr.size, arr.send(method).size
    end
  end

  def test_size_for_enum_created_from_enumerable
    %i[find_all reject map flat_map partition group_by sort_by min_by max_by
      minmax_by each_with_index reverse_each each_entry].each do |method|
      assert_equal nil, @obj.send(method).size
      assert_equal 42, @sized.send(method).size
    end
    assert_equal nil, @obj.each_with_object(nil).size
    assert_equal 42, @sized.each_with_object(nil).size
  end

  def test_size_for_enum_created_from_hash
    h = {a: 1, b: 2, c: 3}
    methods = %i[delete_if reject reject! select select! keep_if each each_key each_pair]
    enums = methods.map {|method| h.send(method)}
    s = enums.group_by(&:size)
    assert_equal([3], s.keys, ->{s.reject!{|k| k==3}.inspect})
    h[:d] = 4
    s = enums.group_by(&:size)
    assert_equal([4], s.keys, ->{s.reject!{|k| k==4}.inspect})
  end

  def test_size_for_enum_created_from_env
    %i[each_pair reject! delete_if select select! keep_if].each do |method|
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
    assert_equal 0,  [].cycle.size
    assert_equal 0,  [].cycle(5).size

    assert_equal nil, @obj.cycle.size
    assert_equal nil, @obj.cycle(5).size
    assert_equal Float::INFINITY, @sized.cycle.size
    assert_equal 126, @sized.cycle(3).size
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
    assert_raise(ArgumentError){ (1..10).step(-2).size }
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
end

