# frozen_string_literal: false
require 'test/unit'

class TestLambdaParameters < Test::Unit::TestCase

  def test_exact_parameter
    assert_raise(ArgumentError){(1..3).each(&lambda{})}
  end

  def test_call_simple
    assert_equal(1, lambda{|a| a}.call(1))
    assert_equal([1,2], lambda{|a, b| [a,b]}.call(1,2))
    assert_raise(ArgumentError) { lambda{|a|}.call(1,2) }
    assert_raise(ArgumentError) { lambda{|a|}.call() }
    assert_raise(ArgumentError) { lambda{}.call(1) }
    assert_raise(ArgumentError) { lambda{|a, b|}.call(1,2,3) }

    assert_equal(1, ->(a){ a }.call(1))
    assert_equal([1,2], ->(a,b){ [a,b] }.call(1,2))
    assert_raise(ArgumentError) { ->(a){ }.call(1,2) }
    assert_raise(ArgumentError) { ->(a){ }.call() }
    assert_raise(ArgumentError) { ->(){ }.call(1) }
    assert_raise(ArgumentError) { ->(a,b){ }.call(1,2,3) }
  end

  def test_lambda_as_iterator
    a = 0
    2.times(&->(_){ a += 1 })
    assert_equal(2, a)
    assert_raise(ArgumentError) {1.times(&->(){ a += 1 })}
    bug9605 = '[ruby-core:61468] [Bug #9605]'
    assert_nothing_raised(ArgumentError, bug9605) {1.times(&->(n){ a += 1 })}
    assert_equal(3, a, bug9605)
    assert_nothing_raised(ArgumentError, bug9605) {
      a = %w(Hi there how are you).each_with_index.detect(&->(w, i) {w.length == 3})
    }
    assert_equal(["how", 2], a, bug9605)
  end

  def test_call_rest_args
    assert_equal([1,2], ->(*a){ a }.call(1,2))
    assert_equal([1,2,[]], ->(a,b,*c){ [a,b,c] }.call(1,2))
    assert_raise(ArgumentError){ ->(a,*b){ }.call() }
  end

  def test_call_opt_args
    assert_equal([1,2,3,4], ->(a,b,c=3,d=4){ [a,b,c,d] }.call(1,2))
    assert_equal([1,2,3,4], ->(a,b,c=0,d=4){ [a,b,c,d] }.call(1,2,3))
    assert_raise(ArgumentError){ ->(a,b=1){ }.call() }
    assert_raise(ArgumentError){ ->(a,b=1){ }.call(1,2,3) }
  end

  def test_call_rest_and_opt
    assert_equal([1,2,3,[]], ->(a,b=2,c=3,*d){ [a,b,c,d] }.call(1))
    assert_equal([1,2,3,[]], ->(a,b=0,c=3,*d){ [a,b,c,d] }.call(1,2))
    assert_equal([1,2,3,[4,5,6]], ->(a,b=0,c=0,*d){ [a,b,c,d] }.call(1,2,3,4,5,6))
    assert_raise(ArgumentError){ ->(a,b=1,*c){ }.call() }
  end

  def test_call_with_block
    f = ->(a,b,c=3,*d,&e){ [a,b,c,d,e.call(d + [a,b,c])] }
    assert_equal([1,2,3,[],6], f.call(1,2){|z| z.inject{|s,x| s+x} } )
    assert_equal(nil, ->(&b){ b }.call)
    foo { puts "bogus block " }
    assert_equal(1, ->(&b){ b.call }.call { 1 })
    _b = nil
    assert_equal(1, ->(&_b){ _b.call }.call { 1 })
    assert_nil(_b)
  end

  def test_call_block_from_lambda
    bug9605 = '[ruby-core:61470] [Bug #9605]'
    plus = ->(x,y) {x+y}
    assert_raise(ArgumentError, bug9605) {proc(&plus).call [1,2]}
  end

  def test_instance_exec
    bug12568 = '[ruby-core:76300] [Bug #12568]'
    assert_nothing_raised(ArgumentError, bug12568) do
      instance_exec([1,2,3], &->(a=[]){ a })
    end
  end

  def test_instance_eval_return
    bug13090 = '[ruby-core:78917] [Bug #13090] cannot return in lambdas'
    x = :ng
    assert_nothing_raised(LocalJumpError) do
      x = instance_eval(&->(_){return :ok})
    end
  ensure
    assert_equal(:ok, x, bug13090)
  end

  def test_instance_exec_return
    bug13090 = '[ruby-core:78917] [Bug #13090] cannot return in lambdas'
    x = :ng
    assert_nothing_raised(LocalJumpError) do
      x = instance_exec(&->(){return :ok})
    end
  ensure
    assert_equal(:ok, x, bug13090)
  end

  def test_arity_error
    assert_raise(ArgumentError, '[Bug #12705]') do
      [1, 2].tap(&lambda {|a, b|})
    end
  end

  def foo
    assert_equal(nil, ->(&b){ b }.call)
  end

  def test_in_basic_object
    bug5966 = '[ruby-core:42349]'
    called = false
    BasicObject.new.instance_eval {->() {called = true}.()}
    assert_equal(true, called, bug5966)
  end

  def test_location_on_error
    bug6151 = '[ruby-core:43314]'
    called = 0
    line, f = __LINE__, lambda do
      called += 1
      true
    end
    e = assert_raise(ArgumentError) do
      f.call(42)
    end
    assert_send([e.backtrace.first, :start_with?, "#{__FILE__}:#{line}:"], bug6151)
    assert_equal(0, called)
    e = assert_raise(ArgumentError) do
      42.times(&f)
    end
    assert_send([e.backtrace.first, :start_with?, "#{__FILE__}:#{line}:"], bug6151)
    assert_equal(0, called)
  end

  def return_in_current(val)
    1.tap(&->(*) {return 0})
    val
  end

  def yield_block
    yield
  end

  def return_in_callee(val)
    yield_block(&->(*) {return 0})
    val
  end

  def test_return
    feature8693 = '[ruby-core:56193] [Feature #8693]'
    assert_equal(42, return_in_current(42), feature8693)
    assert_equal(42, return_in_callee(42), feature8693)
  end

  def break_in_current(val)
    1.tap(&->(*) {break 0})
    val
  end

  def break_in_callee(val)
    yield_block(&->(*) {break 0})
    val
  end

  def test_break
    assert_equal(42, break_in_current(42))
    assert_equal(42, break_in_callee(42))
  end

  def test_do_lambda_source_location
    exp_lineno = __LINE__ + 3
    lmd = ->(x,
             y,
             z) do
      #
    end
    file, lineno = lmd.source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(exp_lineno, lineno, "must be at the beginning of the block")
  end

  def test_brace_lambda_source_location
    exp_lineno = __LINE__ + 3
    lmd = ->(x,
             y,
             z) {
      #
    }
    file, lineno = lmd.source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(exp_lineno, lineno, "must be at the beginning of the block")
  end

  def test_not_orphan_return
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1(&-> { return 42 }) end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { return 42 }).call end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { return 42 }) end }.m2.call)
  end

  def test_not_orphan_break
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1(&-> { break 42 }) end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { break 42 }).call end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { break 42 }) end }.m2.call)
  end

  def test_not_orphan_next
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1(&-> { next 42 }) end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { next 42 }).call end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1(&-> { next 42 }) end }.m2.call)
  end
end
