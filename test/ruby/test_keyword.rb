# frozen_string_literal: false
require 'test/unit'
require '-test-/rb_call_super_kw'
require '-test-/iter'

class TestKeywordArguments < Test::Unit::TestCase
  def f1(str: "foo", num: 424242)
    [str, num]
  end

  def test_f1
    assert_equal(["foo", 424242], f1)
    assert_equal(["bar", 424242], f1(str: "bar"))
    assert_equal(["foo", 111111], f1(num: 111111))
    assert_equal(["bar", 111111], f1(str: "bar", num: 111111))
    assert_raise(ArgumentError) { f1(str: "bar", check: true) }
    assert_raise(ArgumentError) { f1("string") }
  end


  def f2(x, str: "foo", num: 424242)
    [x, str, num]
  end

  def test_f2
    assert_equal([:xyz, "foo", 424242], f2(:xyz))
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `f2'/m) do
      assert_equal([{"bar"=>42}, "foo", 424242], f2("bar"=>42))
    end
  end


  def f3(str: "foo", num: 424242, **h)
    [str, num, h]
  end

  def test_f3
    assert_equal(["foo", 424242, {}], f3)
    assert_equal(["bar", 424242, {}], f3(str: "bar"))
    assert_equal(["foo", 111111, {}], f3(num: 111111))
    assert_equal(["bar", 111111, {}], f3(str: "bar", num: 111111))
    assert_equal(["bar", 424242, {:check=>true}], f3(str: "bar", check: true))
    assert_raise(ArgumentError) { f3("string") }
  end


  define_method(:f4) {|str: "foo", num: 424242| [str, num] }

  def test_f4
    assert_equal(["foo", 424242], f4)
    assert_equal(["bar", 424242], f4(str: "bar"))
    assert_equal(["foo", 111111], f4(num: 111111))
    assert_equal(["bar", 111111], f4(str: "bar", num: 111111))
    assert_raise(ArgumentError) { f4(str: "bar", check: true) }
    assert_raise(ArgumentError) { f4("string") }
  end


  define_method(:f5) {|str: "foo", num: 424242, **h| [str, num, h] }

  def test_f5
    assert_equal(["foo", 424242, {}], f5)
    assert_equal(["bar", 424242, {}], f5(str: "bar"))
    assert_equal(["foo", 111111, {}], f5(num: 111111))
    assert_equal(["bar", 111111, {}], f5(str: "bar", num: 111111))
    assert_equal(["bar", 424242, {:check=>true}], f5(str: "bar", check: true))
    assert_raise(ArgumentError) { f5("string") }
  end


  def f6(str: "foo", num: 424242, **h, &blk)
    [str, num, h, blk]
  end

  def test_f6 # [ruby-core:40518]
    assert_equal(["foo", 424242, {}, nil], f6)
    assert_equal(["bar", 424242, {}, nil], f6(str: "bar"))
    assert_equal(["foo", 111111, {}, nil], f6(num: 111111))
    assert_equal(["bar", 111111, {}, nil], f6(str: "bar", num: 111111))
    assert_equal(["bar", 424242, {:check=>true}, nil], f6(str: "bar", check: true))
    a = f6 {|x| x + 42 }
    assert_equal(["foo", 424242, {}], a[0, 3])
    assert_equal(43, a.last.call(1))
  end

  def f7(*r, str: "foo", num: 424242, **h)
    [r, str, num, h]
  end

  def test_f7 # [ruby-core:41772]
    assert_equal([[], "foo", 424242, {}], f7)
    assert_equal([[], "bar", 424242, {}], f7(str: "bar"))
    assert_equal([[], "foo", 111111, {}], f7(num: 111111))
    assert_equal([[], "bar", 111111, {}], f7(str: "bar", num: 111111))
    assert_equal([[1], "foo", 424242, {}], f7(1))
    assert_equal([[1, 2], "foo", 424242, {}], f7(1, 2))
    assert_equal([[1, 2, 3], "foo", 424242, {}], f7(1, 2, 3))
    assert_equal([[1], "bar", 424242, {}], f7(1, str: "bar"))
    assert_equal([[1, 2], "bar", 424242, {}], f7(1, 2, str: "bar"))
    assert_equal([[1, 2, 3], "bar", 424242, {}], f7(1, 2, 3, str: "bar"))
  end

  define_method(:f8) { |opt = :ion, *rest, key: :word|
    [opt, rest, key]
  }

  def test_f8
    assert_equal([:ion, [], :word], f8)
    assert_equal([1, [], :word], f8(1))
    assert_equal([1, [2], :word], f8(1, 2))
  end

  def f9(r, o=42, *args, p, k: :key, **kw, &b)
    [r, o, args, p, k, kw, b]
  end

  def test_f9
    assert_equal([1, 42, [], 2, :key, {}, nil], f9(1, 2))
    assert_equal([1, 2, [], 3, :key, {}, nil], f9(1, 2, 3))
    assert_equal([1, 2, [3], 4, :key, {}, nil], f9(1, 2, 3, 4))
    assert_equal([1, 2, [3, 4], 5, :key, {str: "bar"}, nil], f9(1, 2, 3, 4, 5, str: "bar"))
  end

  def f10(a: 1, **)
    a
  end

  def test_f10
    assert_equal(42, f10(a: 42))
    assert_equal(1, f10(b: 42))
  end

  def f11(**nil)
    local_variables
  end

  def test_f11
    h = {}

    assert_equal([], f11)
    assert_equal([], f11(**{}))
    assert_equal([], f11(**h))
  end

  def f12(**nil, &b)
    [b, local_variables]
  end

  def test_f12
    h = {}
    b = proc{}

    assert_equal([nil, [:b]], f12)
    assert_equal([nil, [:b]], f12(**{}))
    assert_equal([nil, [:b]], f12(**h))
    assert_equal([b, [:b]], f12(&b))
    assert_equal([b, [:b]], f12(**{}, &b))
    assert_equal([b, [:b]], f12(**h, &b))
  end

  def f13(a, **nil)
    a
  end

  def test_f13
    assert_equal(1, f13(1))
    assert_equal(1, f13(1, **{}))
    assert_raise(ArgumentError) { f13(a: 1) }
    assert_raise(ArgumentError) { f13(1, a: 1) }
    assert_raise(ArgumentError) { f13(**{a: 1}) }
    assert_raise(ArgumentError) { f13(1, **{a: 1}) }
  end

  def test_method_parameters
    assert_equal([[:key, :str], [:key, :num]], method(:f1).parameters);
    assert_equal([[:req, :x], [:key, :str], [:key, :num]], method(:f2).parameters);
    assert_equal([[:key, :str], [:key, :num], [:keyrest, :h]], method(:f3).parameters);
    assert_equal([[:key, :str], [:key, :num]], method(:f4).parameters);
    assert_equal([[:key, :str], [:key, :num], [:keyrest, :h]], method(:f5).parameters);
    assert_equal([[:key, :str], [:key, :num], [:keyrest, :h], [:block, :blk]], method(:f6).parameters);
    assert_equal([[:rest, :r], [:key, :str], [:key, :num], [:keyrest, :h]], method(:f7).parameters);
    assert_equal([[:opt, :opt], [:rest, :rest], [:key, :key]], method(:f8).parameters) # [Bug #7540] [ruby-core:50735]
    assert_equal([[:req, :r], [:opt, :o], [:rest, :args], [:req, :p], [:key, :k],
                  [:keyrest, :kw], [:block, :b]], method(:f9).parameters)
  end

  def test_lambda
    f = ->(str: "foo", num: 424242) { [str, num] }
    assert_equal(["foo", 424242], f[])
    assert_equal(["bar", 424242], f[str: "bar"])
    assert_equal(["foo", 111111], f[num: 111111])
    assert_equal(["bar", 111111], f[str: "bar", num: 111111])
  end

  def test_regular_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(kw, c.m(kw, **kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**{})
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**kw)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end
    assert_equal([h, kw], c.m(h))
    assert_equal([h2, kw], c.m(h2))
    assert_equal([h3, kw], c.m(h3))

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal([1, h], c.m(h))
    end
    assert_equal([h2, kw], c.m(h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal([h2, h], c.m(h3))
    end
  end

  def test_implicit_super_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    sc = Class.new
    c = sc.new
    redef = -> do
      if defined?(c.m)
        class << c
          remove_method(:m)
        end
      end
      eval <<-END
        def c.m(*args, **kw)
          super(*args, **kw)
        end
      END
    end
    redef[]
    sc.class_eval do
      def m(*args)
        args
      end
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    sc.class_eval do
      remove_method(:m)
      def m; end
    end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    sc.class_eval do
      remove_method(:m)
      def m(args)
        args
      end
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**{}))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    sc.class_eval do
      remove_method(:m)
      def m(**args)
        args
      end
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    sc.class_eval do
      remove_method(:m)
      def m(arg, **args)
        [arg, args]
      end
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**{})
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**kw)
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    sc.class_eval do
      remove_method(:m)
      def m(arg=1, **args)
        [arg, args]
      end
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
  end

  def test_explicit_super_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    sc = Class.new
    c = sc.new
    redef = -> do
      if defined?(c.m)
        class << c
          remove_method(:m)
        end
      end
      eval <<-END
        def c.m(*args, **kw)
          super(*args, **kw)
        end
      END
    end
    redef[]
    sc.class_eval do
      def m(*args)
        args
      end
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    sc.class_eval do
      remove_method(:m)
      def m; end
    end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    sc.class_eval do
      remove_method(:m)
      def m(args)
        args
      end
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**{}))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    sc.class_eval do
      remove_method(:m)
      def m(**args)
        args
      end
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    sc.class_eval do
      remove_method(:m)
      def m(arg, **args)
        [arg, args]
      end
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**{})
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.m(**kw)
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    sc.class_eval do
      remove_method(:m)
      def m(arg=1, **args)
        [arg, args]
      end
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
  end

  def test_lambda_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    f = -> { true }
    assert_equal(true, f[**{}])
    assert_equal(true, f[**kw])
    assert_raise(ArgumentError) { f[**h] }
    assert_raise(ArgumentError) { f[a: 1] }
    assert_raise(ArgumentError) { f[**h2] }
    assert_raise(ArgumentError) { f[**h3] }

    f = ->(a) { a }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, f[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, f[**kw])
    end
    assert_equal(h, f[**h])
    assert_equal(h, f[a: 1])
    assert_equal(h2, f[**h2])
    assert_equal(h3, f[**h3])
    assert_equal(h3, f[a: 1, **h2])

    f = ->(**x) { x }
    assert_equal(kw, f[**{}])
    assert_equal(kw, f[**kw])
    assert_equal(h, f[**h])
    assert_equal(h, f[a: 1])
    assert_equal(h2, f[**h2])
    assert_equal(h3, f[**h3])
    assert_equal(h3, f[a: 1, **h2])
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `\[\]'/m) do
      assert_equal(h, f[h])
    end
    assert_raise(ArgumentError) { f[h2] }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `\[\]'/m) do
      assert_raise(ArgumentError) { f[h3] }
    end

    f = ->(a, **x) { [a,x] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([{}, {}], f[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([{}, {}], f[**kw])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([h, {}], f[**h])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([h, {}], f[a: 1])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([h2, {}], f[**h2])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([h3, {}], f[**h3])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `\[\]'/m) do
      assert_equal([h3, {}], f[a: 1, **h2])
    end

    f = ->(a=1, **x) { [a, x] }
    assert_equal([1, kw], f[**{}])
    assert_equal([1, kw], f[**kw])
    assert_equal([1, h], f[**h])
    assert_equal([1, h], f[a: 1])
    assert_equal([1, h2], f[**h2])
    assert_equal([1, h3], f[**h3])
    assert_equal([1, h3], f[a: 1, **h2])
  end

  def test_lambda_method_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    f = -> { true }
    f = f.method(:call)
    assert_equal(true, f[**{}])
    assert_equal(true, f[**kw])
    assert_raise(ArgumentError) { f[**h] }
    assert_raise(ArgumentError) { f[a: 1] }
    assert_raise(ArgumentError) { f[**h2] }
    assert_raise(ArgumentError) { f[**h3] }

    f = ->(a) { a }
    f = f.method(:call)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, f[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, f[**kw])
    end
    assert_equal(h, f[**h])
    assert_equal(h, f[a: 1])
    assert_equal(h2, f[**h2])
    assert_equal(h3, f[**h3])
    assert_equal(h3, f[a: 1, **h2])

    f = ->(**x) { x }
    f = f.method(:call)
    assert_equal(kw, f[**{}])
    assert_equal(kw, f[**kw])
    assert_equal(h, f[**h])
    assert_equal(h, f[a: 1])
    assert_equal(h2, f[**h2])
    assert_equal(h3, f[**h3])
    assert_equal(h3, f[a: 1, **h2])
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal(h, f[h])
    end
    assert_raise(ArgumentError) { f[h2] }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_raise(ArgumentError) { f[h3] }
    end

    f = ->(a, **x) { [a,x] }
    f = f.method(:call)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], f[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], f[**kw])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], f[**h])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], f[a: 1])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, {}], f[**h2])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], f[**h3])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], f[a: 1, **h2])
    end

    f = ->(a=1, **x) { [a, x] }
    f = f.method(:call)
    assert_equal([1, kw], f[**{}])
    assert_equal([1, kw], f[**kw])
    assert_equal([1, h], f[**h])
    assert_equal([1, h], f[a: 1])
    assert_equal([1, h2], f[**h2])
    assert_equal([1, h3], f[**h3])
    assert_equal([1, h3], f[a: 1, **h2])
  end

  def test_Thread_new_kwsplat
    Thread.report_on_exception = false
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    t = Thread
    f = -> { true }
    assert_equal(true, t.new(**{}, &f).value)
    assert_equal(true, t.new(**kw, &f).value)
    assert_raise(ArgumentError) { t.new(**h, &f).value }
    assert_raise(ArgumentError) { t.new(a: 1, &f).value }
    assert_raise(ArgumentError) { t.new(**h2, &f).value }
    assert_raise(ArgumentError) { t.new(**h3, &f).value }

    f = ->(a) { a }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, t.new(**{}, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, t.new(**kw, &f).value)
    end
    assert_equal(h, t.new(**h, &f).value)
    assert_equal(h, t.new(a: 1, &f).value)
    assert_equal(h2, t.new(**h2, &f).value)
    assert_equal(h3, t.new(**h3, &f).value)
    assert_equal(h3, t.new(a: 1, **h2, &f).value)

    f = ->(**x) { x }
    assert_equal(kw, t.new(**{}, &f).value)
    assert_equal(kw, t.new(**kw, &f).value)
    assert_equal(h, t.new(**h, &f).value)
    assert_equal(h, t.new(a: 1, &f).value)
    assert_equal(h2, t.new(**h2, &f).value)
    assert_equal(h3, t.new(**h3, &f).value)
    assert_equal(h3, t.new(a: 1, **h2, &f).value)
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal(h, t.new(h, &f).value)
    end
    assert_raise(ArgumentError) { t.new(h2, &f).value }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_raise(ArgumentError) { t.new(h3, &f).value }
    end

    f = ->(a, **x) { [a,x] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], t.new(**{}, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], t.new(**kw, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], t.new(**h, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], t.new(a: 1, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, {}], t.new(**h2, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], t.new(**h3, &f).value)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], t.new(a: 1, **h2, &f).value)
    end

    f = ->(a=1, **x) { [a, x] }
    assert_equal([1, kw], t.new(**{}, &f).value)
    assert_equal([1, kw], t.new(**kw, &f).value)
    assert_equal([1, h], t.new(**h, &f).value)
    assert_equal([1, h], t.new(a: 1, &f).value)
    assert_equal([1, h2], t.new(**h2, &f).value)
    assert_equal([1, h3], t.new(**h3, &f).value)
    assert_equal([1, h3], t.new(a: 1, **h2, &f).value)
  ensure
    Thread.report_on_exception = true
  end

  def test_Fiber_resume_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    t = Fiber
    f = -> { true }
    assert_equal(true, t.new(&f).resume(**{}))
    assert_equal(true, t.new(&f).resume(**kw))
    assert_raise(ArgumentError) { t.new(&f).resume(**h) }
    assert_raise(ArgumentError) { t.new(&f).resume(a: 1) }
    assert_raise(ArgumentError) { t.new(&f).resume(**h2) }
    assert_raise(ArgumentError) { t.new(&f).resume(**h3) }

    f = ->(a) { a }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, t.new(&f).resume(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, t.new(&f).resume(**kw))
    end
    assert_equal(h, t.new(&f).resume(**h))
    assert_equal(h, t.new(&f).resume(a: 1))
    assert_equal(h2, t.new(&f).resume(**h2))
    assert_equal(h3, t.new(&f).resume(**h3))
    assert_equal(h3, t.new(&f).resume(a: 1, **h2))

    f = ->(**x) { x }
    assert_equal(kw, t.new(&f).resume(**{}))
    assert_equal(kw, t.new(&f).resume(**kw))
    assert_equal(h, t.new(&f).resume(**h))
    assert_equal(h, t.new(&f).resume(a: 1))
    assert_equal(h2, t.new(&f).resume(**h2))
    assert_equal(h3, t.new(&f).resume(**h3))
    assert_equal(h3, t.new(&f).resume(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal(h, t.new(&f).resume(h))
    end
    assert_raise(ArgumentError) { t.new(&f).resume(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_raise(ArgumentError) { t.new(&f).resume(h3) }
    end

    f = ->(a, **x) { [a,x] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], t.new(&f).resume(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], t.new(&f).resume(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], t.new(&f).resume(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], t.new(&f).resume(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, {}], t.new(&f).resume(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], t.new(&f).resume(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], t.new(&f).resume(a: 1, **h2))
    end

    f = ->(a=1, **x) { [a, x] }
    assert_equal([1, kw], t.new(&f).resume(**{}))
    assert_equal([1, kw], t.new(&f).resume(**kw))
    assert_equal([1, h], t.new(&f).resume(**h))
    assert_equal([1, h], t.new(&f).resume(a: 1))
    assert_equal([1, h2], t.new(&f).resume(**h2))
    assert_equal([1, h3], t.new(&f).resume(**h3))
    assert_equal([1, h3], t.new(&f).resume(a: 1, **h2))
  end

  def test_Enumerator_Generator_each_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    g = Enumerator::Generator
    f = ->(_) { true }
    assert_equal(true, g.new(&f).each(**{}))
    assert_equal(true, g.new(&f).each(**kw))
    assert_raise(ArgumentError) { g.new(&f).each(**h) }
    assert_raise(ArgumentError) { g.new(&f).each(a: 1) }
    assert_raise(ArgumentError) { g.new(&f).each(**h2) }
    assert_raise(ArgumentError) { g.new(&f).each(**h3) }

    f = ->(_, a) { a }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, g.new(&f).each(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, g.new(&f).each(**kw))
    end
    assert_equal(h, g.new(&f).each(**h))
    assert_equal(h, g.new(&f).each(a: 1))
    assert_equal(h2, g.new(&f).each(**h2))
    assert_equal(h3, g.new(&f).each(**h3))
    assert_equal(h3, g.new(&f).each(a: 1, **h2))

    f = ->(_, **x) { x }
    assert_equal(kw, g.new(&f).each(**{}))
    assert_equal(kw, g.new(&f).each(**kw))
    assert_equal(h, g.new(&f).each(**h))
    assert_equal(h, g.new(&f).each(a: 1))
    assert_equal(h2, g.new(&f).each(**h2))
    assert_equal(h3, g.new(&f).each(**h3))
    assert_equal(h3, g.new(&f).each(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal(h, g.new(&f).each(h))
    end
    assert_raise(ArgumentError) { g.new(&f).each(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_raise(ArgumentError) { g.new(&f).each(h3) }
    end

    f = ->(_, a, **x) { [a,x] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], g.new(&f).each(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], g.new(&f).each(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], g.new(&f).each(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], g.new(&f).each(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, {}], g.new(&f).each(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], g.new(&f).each(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], g.new(&f).each(a: 1, **h2))
    end

    f = ->(_, a=1, **x) { [a, x] }
    assert_equal([1, kw], g.new(&f).each(**{}))
    assert_equal([1, kw], g.new(&f).each(**kw))
    assert_equal([1, h], g.new(&f).each(**h))
    assert_equal([1, h], g.new(&f).each(a: 1))
    assert_equal([1, h2], g.new(&f).each(**h2))
    assert_equal([1, h3], g.new(&f).each(**h3))
    assert_equal([1, h3], g.new(&f).each(a: 1, **h2))
  end

  def test_Enumerator_Yielder_yield_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    g = Enumerator::Generator
    f = -> { true }
    assert_equal(true, g.new{|y| y.yield(**{})}.each(&f))
    assert_equal(true, g.new{|y| y.yield(**kw)}.each(&f))
    assert_raise(ArgumentError) { g.new{|y| y.yield(**h)}.each(&f) }
    assert_raise(ArgumentError) { g.new{|y| y.yield(a: 1)}.each(&f) }
    assert_raise(ArgumentError) { g.new{|y| y.yield(**h2)}.each(&f) }
    assert_raise(ArgumentError) { g.new{|y| y.yield(**h3)}.each(&f) }

    f = ->(a) { a }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, g.new{|y| y.yield(**{})}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, g.new{|y| y.yield(**kw)}.each(&f))
    end
    assert_equal(h, g.new{|y| y.yield(**h)}.each(&f))
    assert_equal(h, g.new{|y| y.yield(a: 1)}.each(&f))
    assert_equal(h2, g.new{|y| y.yield(**h2)}.each(&f))
    assert_equal(h3, g.new{|y| y.yield(**h3)}.each(&f))
    assert_equal(h3, g.new{|y| y.yield(a: 1, **h2)}.each(&f))

    f = ->(**x) { x }
    assert_equal(kw, g.new{|y| y.yield(**{})}.each(&f))
    assert_equal(kw, g.new{|y| y.yield(**kw)}.each(&f))
    assert_equal(h, g.new{|y| y.yield(**h)}.each(&f))
    assert_equal(h, g.new{|y| y.yield(a: 1)}.each(&f))
    assert_equal(h2, g.new{|y| y.yield(**h2)}.each(&f))
    assert_equal(h3, g.new{|y| y.yield(**h3)}.each(&f))
    assert_equal(h3, g.new{|y| y.yield(a: 1, **h2)}.each(&f))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal(h, g.new{|y| y.yield(h)}.each(&f))
    end
    assert_raise(ArgumentError) { g.new{|y| y.yield(h2)}.each(&f) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_raise(ArgumentError) { g.new{|y| y.yield(h3)}.each(&f) }
    end

    f = ->(a, **x) { [a,x] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], g.new{|y| y.yield(**{})}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([{}, {}], g.new{|y| y.yield(**kw)}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], g.new{|y| y.yield(**h)}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, {}], g.new{|y| y.yield(a: 1)}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, {}], g.new{|y| y.yield(**h2)}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], g.new{|y| y.yield(**h3)}.each(&f))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, {}], g.new{|y| y.yield(a: 1, **h2)}.each(&f))
    end

    f = ->(a=1, **x) { [a, x] }
    assert_equal([1, kw], g.new{|y| y.yield(**{})}.each(&f))
    assert_equal([1, kw], g.new{|y| y.yield(**kw)}.each(&f))
    assert_equal([1, h], g.new{|y| y.yield(**h)}.each(&f))
    assert_equal([1, h], g.new{|y| y.yield(a: 1)}.each(&f))
    assert_equal([1, h2], g.new{|y| y.yield(**h2)}.each(&f))
    assert_equal([1, h3], g.new{|y| y.yield(**h3)}.each(&f))
    assert_equal([1, h3], g.new{|y| y.yield(a: 1, **h2)}.each(&f))
  end

  def test_Class_new_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    sc = Class.new do
      attr_reader :args
      class << self
        alias [] new
      end
    end

    c = Class.new(sc) do
      def initialize(*args)
        @args = args
      end
    end
    assert_equal([], c[**{}].args)
    assert_equal([], c[**kw].args)
    assert_equal([h], c[**h].args)
    assert_equal([h], c[a: 1].args)
    assert_equal([h2], c[**h2].args)
    assert_equal([h3], c[**h3].args)
    assert_equal([h3], c[a: 1, **h2].args)

    c = Class.new(sc) do
      def initialize; end
    end
    assert_nil(c[**{}].args)
    assert_nil(c[**kw].args)
    assert_raise(ArgumentError) { c[**h] }
    assert_raise(ArgumentError) { c[a: 1] }
    assert_raise(ArgumentError) { c[**h2] }
    assert_raise(ArgumentError) { c[**h3] }
    assert_raise(ArgumentError) { c[a: 1, **h2] }

    c = Class.new(sc) do
      def initialize(args)
        @args = args
      end
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal(kw, c[**{}].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal(kw, c[**kw].args)
    end
    assert_equal(h, c[**h].args)
    assert_equal(h, c[a: 1].args)
    assert_equal(h2, c[**h2].args)
    assert_equal(h3, c[**h3].args)
    assert_equal(h3, c[a: 1, **h2].args)

    c = Class.new(sc) do
      def initialize(**args)
        @args = args
      end
    end
    assert_equal(kw, c[**{}].args)
    assert_equal(kw, c[**kw].args)
    assert_equal(h, c[**h].args)
    assert_equal(h, c[a: 1].args)
    assert_equal(h2, c[**h2].args)
    assert_equal(h3, c[**h3].args)
    assert_equal(h3, c[a: 1, **h2].args)
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_equal(h, c[h].args)
    end
    assert_raise(ArgumentError) { c[h2].args }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_raise(ArgumentError) { c[h3].args }
    end

    c = Class.new(sc) do
      def initialize(arg, **args)
        @args = [arg, args]
      end
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([kw, kw], c[**{}].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([kw, kw], c[**kw].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h, kw], c[**h].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h, kw], c[a: 1].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h2, kw], c[**h2].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h3, kw], c[**h3].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h3, kw], c[a: 1, **h2].args)
    end

    c = Class.new(sc) do
      def initialize(arg=1, **args)
        @args = [arg, args]
      end
    end
    assert_equal([1, kw], c[**{}].args)
    assert_equal([1, kw], c[**kw].args)
    assert_equal([1, h], c[**h].args)
    assert_equal([1, h], c[a: 1].args)
    assert_equal([1, h2], c[**h2].args)
    assert_equal([1, h3], c[**h3].args)
    assert_equal([1, h3], c[a: 1, **h2].args)
  end

  def test_Class_new_method_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    sc = Class.new do
      attr_reader :args
    end

    c = Class.new(sc) do
      def initialize(*args)
        @args = args
      end
    end.method(:new)
    assert_equal([], c[**{}].args)
    assert_equal([], c[**kw].args)
    assert_equal([h], c[**h].args)
    assert_equal([h], c[a: 1].args)
    assert_equal([h2], c[**h2].args)
    assert_equal([h3], c[**h3].args)
    assert_equal([h3], c[a: 1, **h2].args)

    c = Class.new(sc) do
      def initialize; end
    end.method(:new)
    assert_nil(c[**{}].args)
    assert_nil(c[**kw].args)
    assert_raise(ArgumentError) { c[**h] }
    assert_raise(ArgumentError) { c[a: 1] }
    assert_raise(ArgumentError) { c[**h2] }
    assert_raise(ArgumentError) { c[**h3] }
    assert_raise(ArgumentError) { c[a: 1, **h2] }

    c = Class.new(sc) do
      def initialize(args)
        @args = args
      end
    end.method(:new)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal(kw, c[**{}].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal(kw, c[**kw].args)
    end
    assert_equal(h, c[**h].args)
    assert_equal(h, c[a: 1].args)
    assert_equal(h2, c[**h2].args)
    assert_equal(h3, c[**h3].args)
    assert_equal(h3, c[a: 1, **h2].args)

    c = Class.new(sc) do
      def initialize(**args)
        @args = args
      end
    end.method(:new)
    assert_equal(kw, c[**{}].args)
    assert_equal(kw, c[**kw].args)
    assert_equal(h, c[**h].args)
    assert_equal(h, c[a: 1].args)
    assert_equal(h2, c[**h2].args)
    assert_equal(h3, c[**h3].args)
    assert_equal(h3, c[a: 1, **h2].args)
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_equal(h, c[h].args)
    end
    assert_raise(ArgumentError) { c[h2].args }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_raise(ArgumentError) { c[h3].args }
    end

    c = Class.new(sc) do
      def initialize(arg, **args)
        @args = [arg, args]
      end
    end.method(:new)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([kw, kw], c[**{}].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([kw, kw], c[**kw].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h, kw], c[**h].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h, kw], c[a: 1].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h2, kw], c[**h2].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h3, kw], c[**h3].args)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `initialize'/m) do
      assert_equal([h3, kw], c[a: 1, **h2].args)
    end

    c = Class.new(sc) do
      def initialize(arg=1, **args)
        @args = [arg, args]
      end
    end.method(:new)
    assert_equal([1, kw], c[**{}].args)
    assert_equal([1, kw], c[**kw].args)
    assert_equal([1, h], c[**h].args)
    assert_equal([1, h], c[a: 1].args)
    assert_equal([1, h2], c[**h2].args)
    assert_equal([1, h3], c[**h3].args)
    assert_equal([1, h3], c[a: 1, **h2].args)
  end

  def test_Method_call_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], c.method(:m)[**{}])
    assert_equal([], c.method(:m)[**kw])
    assert_equal([h], c.method(:m)[**h])
    assert_equal([h], c.method(:m)[a: 1])
    assert_equal([h2], c.method(:m)[**h2])
    assert_equal([h3], c.method(:m)[**h3])
    assert_equal([h3], c.method(:m)[a: 1, **h2])

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(c.method(:m)[**{}])
    assert_nil(c.method(:m)[**kw])
    assert_raise(ArgumentError) { c.method(:m)[**h] }
    assert_raise(ArgumentError) { c.method(:m)[a: 1] }
    assert_raise(ArgumentError) { c.method(:m)[**h2] }
    assert_raise(ArgumentError) { c.method(:m)[**h3] }
    assert_raise(ArgumentError) { c.method(:m)[a: 1, **h2] }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.method(:m)[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.method(:m)[**kw])
    end
    assert_equal(h, c.method(:m)[**h])
    assert_equal(h, c.method(:m)[a: 1])
    assert_equal(h2, c.method(:m)[**h2])
    assert_equal(h3, c.method(:m)[**h3])
    assert_equal(h3, c.method(:m)[a: 1, **h2])

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.method(:m)[**{}])
    assert_equal(kw, c.method(:m)[**kw])
    assert_equal(h, c.method(:m)[**h])
    assert_equal(h, c.method(:m)[a: 1])
    assert_equal(h2, c.method(:m)[**h2])
    assert_equal(h3, c.method(:m)[**h3])
    assert_equal(h3, c.method(:m)[a: 1, **h2])
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.method(:m)[h])
    end
    assert_raise(ArgumentError) { c.method(:m)[h2] }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.method(:m)[h3] }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], c.method(:m)[**{}])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], c.method(:m)[**kw])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.method(:m)[**h])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.method(:m)[a: 1])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.method(:m)[**h2])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.method(:m)[**h3])
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.method(:m)[a: 1, **h2])
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.method(:m)[**{}])
    assert_equal([1, kw], c.method(:m)[**kw])
    assert_equal([1, h], c.method(:m)[**h])
    assert_equal([1, h], c.method(:m)[a: 1])
    assert_equal([1, h2], c.method(:m)[**h2])
    assert_equal([1, h3], c.method(:m)[**h3])
    assert_equal([1, h3], c.method(:m)[a: 1, **h2])
  end

  def test_UnboundMethod_bindcall_kwsplat_call
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    sc = c.singleton_class
    def c.m(*args)
      args
    end
    assert_equal([], sc.instance_method(:m).bind_call(c, **{}))
    assert_equal([], sc.instance_method(:m).bind_call(c, **kw))
    assert_equal([h], sc.instance_method(:m).bind_call(c, **h))
    assert_equal([h], sc.instance_method(:m).bind_call(c, a: 1))
    assert_equal([h2], sc.instance_method(:m).bind_call(c, **h2))
    assert_equal([h3], sc.instance_method(:m).bind_call(c, **h3))
    assert_equal([h3], sc.instance_method(:m).bind_call(c, a: 1, **h2))

    sc.remove_method(:m)
    def c.m; end
    assert_nil(sc.instance_method(:m).bind_call(c, **{}))
    assert_nil(sc.instance_method(:m).bind_call(c, **kw))
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, **h) }
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, a: 1) }
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, **h2) }
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, **h3) }
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, a: 1, **h2) }

    sc.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, sc.instance_method(:m).bind_call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, sc.instance_method(:m).bind_call(c, **kw))
    end
    assert_equal(h, sc.instance_method(:m).bind_call(c, **h))
    assert_equal(h, sc.instance_method(:m).bind_call(c, a: 1))
    assert_equal(h2, sc.instance_method(:m).bind_call(c, **h2))
    assert_equal(h3, sc.instance_method(:m).bind_call(c, **h3))
    assert_equal(h3, sc.instance_method(:m).bind_call(c, a: 1, **h2))

    sc.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, sc.instance_method(:m).bind_call(c, **{}))
    assert_equal(kw, sc.instance_method(:m).bind_call(c, **kw))
    assert_equal(h, sc.instance_method(:m).bind_call(c, **h))
    assert_equal(h, sc.instance_method(:m).bind_call(c, a: 1))
    assert_equal(h2, sc.instance_method(:m).bind_call(c, **h2))
    assert_equal(h3, sc.instance_method(:m).bind_call(c, **h3))
    assert_equal(h3, sc.instance_method(:m).bind_call(c, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, sc.instance_method(:m).bind_call(c, h))
    end
    assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { sc.instance_method(:m).bind_call(c, h3) }
    end

    sc.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], sc.instance_method(:m).bind_call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], sc.instance_method(:m).bind_call(c, **kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], sc.instance_method(:m).bind_call(c, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], sc.instance_method(:m).bind_call(c, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], sc.instance_method(:m).bind_call(c, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], sc.instance_method(:m).bind_call(c, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], sc.instance_method(:m).bind_call(c, a: 1, **h2))
    end

    sc.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], sc.instance_method(:m).bind_call(c, **{}))
    assert_equal([1, kw], sc.instance_method(:m).bind_call(c, **kw))
    assert_equal([1, h], sc.instance_method(:m).bind_call(c, **h))
    assert_equal([1, h], sc.instance_method(:m).bind_call(c, a: 1))
    assert_equal([1, h2], sc.instance_method(:m).bind_call(c, **h2))
    assert_equal([1, h3], sc.instance_method(:m).bind_call(c, **h3))
    assert_equal([1, h3], sc.instance_method(:m).bind_call(c, a: 1, **h2))
  end

  def test_send_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], c.send(:m, **{}))
    assert_equal([], c.send(:m, **kw))
    assert_equal([h], c.send(:m, **h))
    assert_equal([h], c.send(:m, a: 1))
    assert_equal([h2], c.send(:m, **h2))
    assert_equal([h3], c.send(:m, **h3))
    assert_equal([h3], c.send(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(c.send(:m, **{}))
    assert_nil(c.send(:m, **kw))
    assert_raise(ArgumentError) { c.send(:m, **h) }
    assert_raise(ArgumentError) { c.send(:m, a: 1) }
    assert_raise(ArgumentError) { c.send(:m, **h2) }
    assert_raise(ArgumentError) { c.send(:m, **h3) }
    assert_raise(ArgumentError) { c.send(:m, a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.send(:m, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.send(:m, **kw))
    end
    assert_equal(h, c.send(:m, **h))
    assert_equal(h, c.send(:m, a: 1))
    assert_equal(h2, c.send(:m, **h2))
    assert_equal(h3, c.send(:m, **h3))
    assert_equal(h3, c.send(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.send(:m, **{}))
    assert_equal(kw, c.send(:m, **kw))
    assert_equal(h, c.send(:m, **h))
    assert_equal(h, c.send(:m, a: 1))
    assert_equal(h2, c.send(:m, **h2))
    assert_equal(h3, c.send(:m, **h3))
    assert_equal(h3, c.send(:m, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.send(:m, h))
    end
    assert_raise(ArgumentError) { c.send(:m, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.send(:m, h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.send(:m, **{})
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.send(:m, **kw)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.send(:m, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.send(:m, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.send(:m, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.send(:m, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.send(:m, a: 1, **h2))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.send(:m, **{}))
    assert_equal([1, kw], c.send(:m, **kw))
    assert_equal([1, h], c.send(:m, **h))
    assert_equal([1, h], c.send(:m, a: 1))
    assert_equal([1, h2], c.send(:m, **h2))
    assert_equal([1, h3], c.send(:m, **h3))
    assert_equal([1, h3], c.send(:m, a: 1, **h2))
  end

  def test_public_send_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], c.public_send(:m, **{}))
    assert_equal([], c.public_send(:m, **kw))
    assert_equal([h], c.public_send(:m, **h))
    assert_equal([h], c.public_send(:m, a: 1))
    assert_equal([h2], c.public_send(:m, **h2))
    assert_equal([h3], c.public_send(:m, **h3))
    assert_equal([h3], c.public_send(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(c.public_send(:m, **{}))
    assert_nil(c.public_send(:m, **kw))
    assert_raise(ArgumentError) { c.public_send(:m, **h) }
    assert_raise(ArgumentError) { c.public_send(:m, a: 1) }
    assert_raise(ArgumentError) { c.public_send(:m, **h2) }
    assert_raise(ArgumentError) { c.public_send(:m, **h3) }
    assert_raise(ArgumentError) { c.public_send(:m, a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.public_send(:m, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.public_send(:m, **kw))
    end
    assert_equal(h, c.public_send(:m, **h))
    assert_equal(h, c.public_send(:m, a: 1))
    assert_equal(h2, c.public_send(:m, **h2))
    assert_equal(h3, c.public_send(:m, **h3))
    assert_equal(h3, c.public_send(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.public_send(:m, **{}))
    assert_equal(kw, c.public_send(:m, **kw))
    assert_equal(h, c.public_send(:m, **h))
    assert_equal(h, c.public_send(:m, a: 1))
    assert_equal(h2, c.public_send(:m, **h2))
    assert_equal(h3, c.public_send(:m, **h3))
    assert_equal(h3, c.public_send(:m, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.public_send(:m, h))
    end
    assert_raise(ArgumentError) { c.public_send(:m, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.public_send(:m, h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.public_send(:m, **{})
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      c.public_send(:m, **kw)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.public_send(:m, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.public_send(:m, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.public_send(:m, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.public_send(:m, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.public_send(:m, a: 1, **h2))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.public_send(:m, **{}))
    assert_equal([1, kw], c.public_send(:m, **kw))
    assert_equal([1, h], c.public_send(:m, **h))
    assert_equal([1, h], c.public_send(:m, a: 1))
    assert_equal([1, h2], c.public_send(:m, **h2))
    assert_equal([1, h3], c.public_send(:m, **h3))
    assert_equal([1, h3], c.public_send(:m, a: 1, **h2))
  end

  def test_send_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    m = c.method(:send)
    assert_equal([], m.call(:m, **{}))
    assert_equal([], m.call(:m, **kw))
    assert_equal([h], m.call(:m, **h))
    assert_equal([h], m.call(:m, a: 1))
    assert_equal([h2], m.call(:m, **h2))
    assert_equal([h3], m.call(:m, **h3))
    assert_equal([h3], m.call(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    m = c.method(:send)
    assert_nil(m.call(:m, **{}))
    assert_nil(m.call(:m, **kw))
    assert_raise(ArgumentError) { m.call(:m, **h) }
    assert_raise(ArgumentError) { m.call(:m, a: 1) }
    assert_raise(ArgumentError) { m.call(:m, **h2) }
    assert_raise(ArgumentError) { m.call(:m, **h3) }
    assert_raise(ArgumentError) { m.call(:m, a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    m = c.method(:send)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, m.call(:m, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, m.call(:m, **kw))
    end
    assert_equal(h, m.call(:m, **h))
    assert_equal(h, m.call(:m, a: 1))
    assert_equal(h2, m.call(:m, **h2))
    assert_equal(h3, m.call(:m, **h3))
    assert_equal(h3, m.call(:m, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    m = c.method(:send)
    assert_equal(kw, m.call(:m, **{}))
    assert_equal(kw, m.call(:m, **kw))
    assert_equal(h, m.call(:m, **h))
    assert_equal(h, m.call(:m, a: 1))
    assert_equal(h2, m.call(:m, **h2))
    assert_equal(h3, m.call(:m, **h3))
    assert_equal(h3, m.call(:m, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, m.call(:m, h))
    end
    assert_raise(ArgumentError) { m.call(:m, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { m.call(:m, h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    m = c.method(:send)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      m.call(:m, **{})
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      m.call(:m, **kw)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], m.call(:m, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], m.call(:m, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], m.call(:m, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], m.call(:m, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], m.call(:m, a: 1, **h2))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    m = c.method(:send)
    assert_equal([1, kw], m.call(:m, **{}))
    assert_equal([1, kw], m.call(:m, **kw))
    assert_equal([1, h], m.call(:m, **h))
    assert_equal([1, h], m.call(:m, a: 1))
    assert_equal([1, h2], m.call(:m, **h2))
    assert_equal([1, h3], m.call(:m, **h3))
    assert_equal([1, h3], m.call(:m, a: 1, **h2))
  end

  def test_sym_proc_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], :m.to_proc.call(c, **{}))
    assert_equal([], :m.to_proc.call(c, **kw))
    assert_equal([h], :m.to_proc.call(c, **h))
    assert_equal([h], :m.to_proc.call(c, a: 1))
    assert_equal([h2], :m.to_proc.call(c, **h2))
    assert_equal([h3], :m.to_proc.call(c, **h3))
    assert_equal([h3], :m.to_proc.call(c, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(:m.to_proc.call(c, **{}))
    assert_nil(:m.to_proc.call(c, **kw))
    assert_raise(ArgumentError) { :m.to_proc.call(c, **h) }
    assert_raise(ArgumentError) { :m.to_proc.call(c, a: 1) }
    assert_raise(ArgumentError) { :m.to_proc.call(c, **h2) }
    assert_raise(ArgumentError) { :m.to_proc.call(c, **h3) }
    assert_raise(ArgumentError) { :m.to_proc.call(c, a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, :m.to_proc.call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, :m.to_proc.call(c, **kw))
    end
    assert_equal(h, :m.to_proc.call(c, **h))
    assert_equal(h, :m.to_proc.call(c, a: 1))
    assert_equal(h2, :m.to_proc.call(c, **h2))
    assert_equal(h3, :m.to_proc.call(c, **h3))
    assert_equal(h3, :m.to_proc.call(c, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, :m.to_proc.call(c, **{}))
    assert_equal(kw, :m.to_proc.call(c, **kw))
    assert_equal(h, :m.to_proc.call(c, **h))
    assert_equal(h, :m.to_proc.call(c, a: 1))
    assert_equal(h2, :m.to_proc.call(c, **h2))
    assert_equal(h3, :m.to_proc.call(c, **h3))
    assert_equal(h3, :m.to_proc.call(c, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, :m.to_proc.call(c, h))
    end
    assert_raise(ArgumentError) { :m.to_proc.call(c, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { :m.to_proc.call(c, h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], :m.to_proc.call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], :m.to_proc.call(c, **kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], :m.to_proc.call(c, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], :m.to_proc.call(c, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], :m.to_proc.call(c, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], :m.to_proc.call(c, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], :m.to_proc.call(c, a: 1, **h2))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], :m.to_proc.call(c, **{}))
    assert_equal([1, kw], :m.to_proc.call(c, **kw))
    assert_equal([1, h], :m.to_proc.call(c, **h))
    assert_equal([1, h], :m.to_proc.call(c, a: 1))
    assert_equal([1, h2], :m.to_proc.call(c, **h2))
    assert_equal([1, h3], :m.to_proc.call(c, **h3))
    assert_equal([1, h3], :m.to_proc.call(c, a: 1, **h2))
  end

  def test_sym_proc_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    m = :m.to_proc.method(:call)
    assert_equal([], m.call(c, **{}))
    assert_equal([], m.call(c, **kw))
    assert_equal([h], m.call(c, **h))
    assert_equal([h], m.call(c, a: 1))
    assert_equal([h2], m.call(c, **h2))
    assert_equal([h3], m.call(c, **h3))
    assert_equal([h3], m.call(c, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(m.call(c, **{}))
    assert_nil(m.call(c, **kw))
    assert_raise(ArgumentError) { m.call(c, **h) }
    assert_raise(ArgumentError) { m.call(c, a: 1) }
    assert_raise(ArgumentError) { m.call(c, **h2) }
    assert_raise(ArgumentError) { m.call(c, **h3) }
    assert_raise(ArgumentError) { m.call(c, a: 1, **h2) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, m.call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, m.call(c, **kw))
    end
    assert_equal(h, m.call(c, **h))
    assert_equal(h, m.call(c, a: 1))
    assert_equal(h2, m.call(c, **h2))
    assert_equal(h3, m.call(c, **h3))
    assert_equal(h3, m.call(c, a: 1, **h2))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, m.call(c, **{}))
    assert_equal(kw, m.call(c, **kw))
    assert_equal(h, m.call(c, **h))
    assert_equal(h, m.call(c, a: 1))
    assert_equal(h2, m.call(c, **h2))
    assert_equal(h3, m.call(c, **h3))
    assert_equal(h3, m.call(c, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, m.call(c, h))
    end
    assert_raise(ArgumentError) { m.call(c, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { m.call(c, h3) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], m.call(c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], m.call(c, **kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], m.call(c, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], m.call(c, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], m.call(c, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], m.call(c, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], m.call(c, a: 1, **h2))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], m.call(c, **{}))
    assert_equal([1, kw], m.call(c, **kw))
    assert_equal([1, h], m.call(c, **h))
    assert_equal([1, h], m.call(c, a: 1))
    assert_equal([1, h2], m.call(c, **h2))
    assert_equal([1, h3], m.call(c, **h3))
    assert_equal([1, h3], m.call(c, a: 1, **h2))
  end

  def test_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.method_missing(_, *args)
      args
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_); end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
  end

  def test_super_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Class.new do
      def m(*args, **kw)
        super
      end
    end.new
    def c.method_missing(_, *args)
      args
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_); end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, args)
          args
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**{}))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `m'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, arg, **args)
          [arg, args]
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**{}))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**kw))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
  end

  def test_rb_call_super_kw_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    c.extend Bug::RbCallSuperKw
    def c.method_missing(_, *args)
      args
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_); end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.m(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))
  end

  def test_define_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      define_method(:m) { }
    end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }

    c = Object.new
    class << c
      define_method(:m) {|arg| arg }
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, c.m(**kw))
    end
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|*args| args }
    end
    assert_equal([], c.m(**{}))
    assert_equal([], c.m(**kw))
    assert_equal([h], c.m(**h))
    assert_equal([h], c.m(a: 1))
    assert_equal([h2], c.m(**h2))
    assert_equal([h3], c.m(**h3))
    assert_equal([h3], c.m(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|**opt| opt}
    end
    assert_equal(kw, c.m(**{}))
    assert_equal(kw, c.m(**kw))
    assert_equal(h, c.m(**h))
    assert_equal(h, c.m(a: 1))
    assert_equal(h2, c.m(**h2))
    assert_equal(h3, c.m(**h3))
    assert_equal(h3, c.m(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal(h, c.m(h))
    end
    assert_raise(ArgumentError) { c.m(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/m) do
      assert_raise(ArgumentError) { c.m(h3) }
    end

    c = Object.new
    class << c
      define_method(:m) {|arg, **opt| [arg, opt] }
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([kw, kw], c.m(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([kw, kw], c.m(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], c.m(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], c.m(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h2, kw], c.m(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], c.m(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], c.m(a: 1, **h2))
    end

    c = Object.new
    class << c
      define_method(:m) {|arg=1, **opt| [arg, opt] }
    end
    assert_equal([1, kw], c.m(**{}))
    assert_equal([1, kw], c.m(**kw))
    assert_equal([1, h], c.m(**h))
    assert_equal([1, h], c.m(a: 1))
    assert_equal([1, h2], c.m(**h2))
    assert_equal([1, h3], c.m(**h3))
    assert_equal([1, h3], c.m(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|*args, **opt| [args, opt] }
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[], h], c.m(h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[h], h], c.m(h, h))
    end

    c = Object.new
    class << c
      define_method(:m) {|arg=nil, a: nil| [arg, a] }
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([h2, 1], c.m(h3))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([h2, 1], c.m(**h3))
    end
  end

  def test_define_method_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      define_method(:m) { }
    end
    m = c.method(:m)
    assert_nil(m.call(**{}))
    assert_nil(m.call(**kw))
    assert_raise(ArgumentError) { m.call(**h) }
    assert_raise(ArgumentError) { m.call(a: 1) }
    assert_raise(ArgumentError) { m.call(**h2) }
    assert_raise(ArgumentError) { m.call(**h3) }
    assert_raise(ArgumentError) { m.call(a: 1, **h2) }

    c = Object.new
    class << c
      define_method(:m) {|arg| arg }
    end
    m = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, m.call(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, m.call(**kw))
    end
    assert_equal(h, m.call(**h))
    assert_equal(h, m.call(a: 1))
    assert_equal(h2, m.call(**h2))
    assert_equal(h3, m.call(**h3))
    assert_equal(h3, m.call(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|*args| args }
    end
    m = c.method(:m)
    assert_equal([], m.call(**{}))
    assert_equal([], m.call(**kw))
    assert_equal([h], m.call(**h))
    assert_equal([h], m.call(a: 1))
    assert_equal([h2], m.call(**h2))
    assert_equal([h3], m.call(**h3))
    assert_equal([h3], m.call(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|**opt| opt}
    end
    m = c.method(:m)
    assert_equal(kw, m.call(**{}))
    assert_equal(kw, m.call(**kw))
    assert_equal(h, m.call(**h))
    assert_equal(h, m.call(a: 1))
    assert_equal(h2, m.call(**h2))
    assert_equal(h3, m.call(**h3))
    assert_equal(h3, m.call(a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal(h, m.call(h))
    end
    assert_raise(ArgumentError) { m.call(h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/m) do
      assert_raise(ArgumentError) { m.call(h3) }
    end

    c = Object.new
    class << c
      define_method(:m) {|arg, **opt| [arg, opt] }
    end
    m = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([kw, kw], m.call(**{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([kw, kw], m.call(**kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], m.call(**h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], m.call(a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h2, kw], m.call(**h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], m.call(**h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], m.call(a: 1, **h2))
    end

    c = Object.new
    class << c
      define_method(:m) {|arg=1, **opt| [arg, opt] }
    end
    m = c.method(:m)
    assert_equal([1, kw], m.call(**{}))
    assert_equal([1, kw], m.call(**kw))
    assert_equal([1, h], m.call(**h))
    assert_equal([1, h], m.call(a: 1))
    assert_equal([1, h2], m.call(**h2))
    assert_equal([1, h3], m.call(**h3))
    assert_equal([1, h3], m.call(a: 1, **h2))

    c = Object.new
    class << c
      define_method(:m) {|*args, **opt| [args, opt] }
    end
    m = c.method(:m)
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[], h], m.call(h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[h], h], m.call(h, h))
    end

    c = Object.new
    class << c
      define_method(:m) {|arg=nil, a: nil| [arg, a] }
    end
    m = c.method(:m)
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([h2, 1], m.call(h3))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([h2, 1], m.call(**h3))
    end
  end

  def test_attr_reader_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      attr_reader :m
    end
    assert_nil(c.m(**{}))
    assert_nil(c.m(**kw))
    assert_raise(ArgumentError) { c.m(**h) }
    assert_raise(ArgumentError) { c.m(a: 1) }
    assert_raise(ArgumentError) { c.m(**h2) }
    assert_raise(ArgumentError) { c.m(**h3) }
    assert_raise(ArgumentError) { c.m(a: 1, **h2) }
  end

  def test_attr_reader_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      attr_reader :m
    end
    m = c.method(:m)
    assert_nil(m.call(**{}))
    assert_nil(m.call(**kw))
    assert_raise(ArgumentError) { m.call(**h) }
    assert_raise(ArgumentError) { m.call(a: 1) }
    assert_raise(ArgumentError) { m.call(**h2) }
    assert_raise(ArgumentError) { m.call(**h3) }
    assert_raise(ArgumentError) { m.call(a: 1, **h2) }
  end

  def test_attr_writer_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      attr_writer :m
    end
    assert_warn(/Passing the keyword argument for `m=' as the last hash parameter is deprecated/) do
      c.send(:m=, **{})
    end
    assert_warn(/Passing the keyword argument for `m=' as the last hash parameter is deprecated/) do
      c.send(:m=, **kw)
    end
    assert_equal(h, c.send(:m=, **h))
    assert_equal(h, c.send(:m=, a: 1))
    assert_equal(h2, c.send(:m=, **h2))
    assert_equal(h3, c.send(:m=, **h3))
    assert_equal(h3, c.send(:m=, a: 1, **h2))

    assert_equal(42, c.send(:m=, 42, **{}))
    assert_equal(42, c.send(:m=, 42, **kw))
    assert_raise(ArgumentError) { c.send(:m=, 42, **h) }
    assert_raise(ArgumentError) { c.send(:m=, 42, a: 1) }
    assert_raise(ArgumentError) { c.send(:m=, 42, **h2) }
    assert_raise(ArgumentError) { c.send(:m=, 42, **h3) }
    assert_raise(ArgumentError) { c.send(:m=, 42, a: 1, **h2) }
  end

  def test_attr_writer_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    class << c
      attr_writer :m
    end
    m = c.method(:m=)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      m.call(**{})
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      m.call(**kw)
    end
    assert_equal(h, m.call(**h))
    assert_equal(h, m.call(a: 1))
    assert_equal(h2, m.call(**h2))
    assert_equal(h3, m.call(**h3))
    assert_equal(h3, m.call(a: 1, **h2))

    assert_equal(42, m.call(42, **{}))
    assert_equal(42, m.call(42, **kw))
    assert_raise(ArgumentError) { m.call(42, **h) }
    assert_raise(ArgumentError) { m.call(42, a: 1) }
    assert_raise(ArgumentError) { m.call(42, **h2) }
    assert_raise(ArgumentError) { m.call(42, **h3) }
    assert_raise(ArgumentError) { m.call(42, a: 1, **h2) }
  end

  def test_proc_ruby2_keywords
    h1 = {:a=>1}
    foo = ->(*args, &block){block.call(*args)}
    assert_same(foo, foo.ruby2_keywords)

    assert_equal([[1], h1], foo.call(1, :a=>1, &->(*args, **kw){[args, kw]}))
    assert_equal([1, h1], foo.call(1, :a=>1, &->(*args){args}))
    assert_warn(/Using the last argument as keyword parameters is deprecated/) do
      assert_equal([[1], h1], foo.call(1, {:a=>1}, &->(*args, **kw){[args, kw]}))
    end
    assert_equal([1, h1], foo.call(1, {:a=>1}, &->(*args){args}))
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h1, {}], foo.call(:a=>1, &->(arg, **kw){[arg, kw]}))
    end
    assert_equal(h1, foo.call(:a=>1, &->(arg){arg}))

    [->(){}, ->(arg){}, ->(*args, **kw){}, ->(*args, k: 1){}, ->(*args, k: ){}].each do |pr|
      assert_warn(/Skipping set of ruby2_keywords flag for proc \(proc accepts keywords or proc does not accept argument splat\)/) do
        pr.ruby2_keywords
      end
    end

    o = Object.new
    def o.foo(*args)
      yield(*args)
    end
    foo = o.method(:foo).to_proc
    assert_warn(/Skipping set of ruby2_keywords flag for proc \(proc created from method\)/) do
      foo.ruby2_keywords
    end

    foo = :foo.to_proc
    assert_warn(/Skipping set of ruby2_keywords flag for proc \(proc not defined in Ruby\)/) do
      foo.ruby2_keywords
    end

    assert_raise(FrozenError) { ->(*args){}.freeze.ruby2_keywords }
  end

  def test_ruby2_keywords
    c = Class.new do
      ruby2_keywords def foo(meth, *args)
        send(meth, *args)
      end

      ruby2_keywords(define_method(:bfoo) do |meth, *args|
        send(meth, *args)
      end)

      ruby2_keywords def foo_bar(*args)
        bar(*args)
      end

      ruby2_keywords def foo_baz(*args)
        baz(*args)
      end

      ruby2_keywords def foo_baz2(*args)
        baz(*args)
        baz(*args)
      end

      ruby2_keywords def foo_foo_bar(meth, *args)
        foo_bar(meth, *args)
      end

      ruby2_keywords def foo_foo_baz(meth, *args)
        foo_baz(meth, *args)
      end

      ruby2_keywords def foo_mod(meth, *args)
        args << 1
        send(meth, *args)
      end

      ruby2_keywords def foo_bar_mod(*args)
        args << 1
        bar(*args)
      end

      ruby2_keywords def foo_baz_mod(*args)
        args << 1
        baz(*args)
      end

      def pass_bar(*args)
        bar(*args)
      end

      def bar(*args, **kw)
        [args, kw]
      end

      def baz(*args)
        args
      end

      ruby2_keywords def foo_dbar(*args)
        dbar(*args)
      end

      ruby2_keywords def foo_dbaz(*args)
        dbaz(*args)
      end

      define_method(:dbar) do |*args, **kw|
        [args, kw]
      end

      define_method(:dbaz) do |*args|
        args
      end

      def pass_cfunc(*args)
        self.class.new(*args).init_args
      end

      ruby2_keywords def block(*args)
        ->(*args, **kw){[args, kw]}.(*args)
      end

      ruby2_keywords def cfunc(*args)
        self.class.new(*args).init_args
      end

      ruby2_keywords def store_foo(meth, *args)
        @stored_args = args
        use(meth)
      end
      def use(meth)
        send(meth, *@stored_args)
      end

      attr_reader :init_args
      def initialize(*args, **kw)
        @init_args = [args, kw]
      end
    end

    mmkw = Class.new do
      def method_missing(*args, **kw)
        [args, kw]
      end
    end

    mmnokw = Class.new do
      def method_missing(*args)
        args
      end
    end

    implicit_super = Class.new(c) do
      ruby2_keywords def bar(*args)
        super
      end

      ruby2_keywords def baz(*args)
        super
      end
    end

    explicit_super = Class.new(c) do
      ruby2_keywords def bar(*args)
        super(*args)
      end

      ruby2_keywords def baz(*args)
        super(*args)
      end
    end

    h1 = {a: 1}
    o = c.new

    assert_equal([1, h1], o.foo_baz2(1, :a=>1))
    assert_equal([1], o.foo_baz2(1, **{}))
    assert_equal([h1], o.foo_baz2(h1, **{}))

    assert_equal([[1], h1], o.foo(:bar, 1, :a=>1))
    assert_equal([1, h1], o.foo(:baz, 1, :a=>1))
    assert_equal([[1], h1], o.bfoo(:bar, 1, :a=>1))
    assert_equal([1, h1], o.bfoo(:baz, 1, :a=>1))
    assert_equal([[1], h1], o.store_foo(:bar, 1, :a=>1))
    assert_equal([1, h1], o.store_foo(:baz, 1, :a=>1))
    assert_equal([[1], h1], o.foo_bar(1, :a=>1))
    assert_equal([1, h1], o.foo_baz(1, :a=>1))
    assert_equal([[1], h1], o.foo(:foo, :bar, 1, :a=>1))
    assert_equal([1, h1], o.foo(:foo, :baz, 1, :a=>1))
    assert_equal([[1], h1], o.foo(:foo_bar, 1, :a=>1))
    assert_equal([1, h1], o.foo(:foo_baz, 1, :a=>1))
    assert_equal([[1], h1], o.foo_foo_bar(1, :a=>1))
    assert_equal([1, h1], o.foo_foo_baz(1, :a=>1))

    assert_equal([[1], h1], o.foo(:bar, 1, **h1))
    assert_equal([1, h1], o.foo(:baz, 1, **h1))
    assert_equal([[1], h1], o.bfoo(:bar, 1, **h1))
    assert_equal([1, h1], o.bfoo(:baz, 1, **h1))
    assert_equal([[1], h1], o.store_foo(:bar, 1, **h1))
    assert_equal([1, h1], o.store_foo(:baz, 1, **h1))
    assert_equal([[1], h1], o.foo_bar(1, **h1))
    assert_equal([1, h1], o.foo_baz(1, **h1))
    assert_equal([[1], h1], o.foo(:foo, :bar, 1, **h1))
    assert_equal([1, h1], o.foo(:foo, :baz, 1, **h1))
    assert_equal([[1], h1], o.foo(:foo_bar, 1, **h1))
    assert_equal([1, h1], o.foo(:foo_baz, 1, **h1))
    assert_equal([[1], h1], o.foo_foo_bar(1, **h1))
    assert_equal([1, h1], o.foo_foo_baz(1, **h1))

    assert_equal([[h1], {}], o.foo(:bar, h1, **{}))
    assert_equal([h1], o.foo(:baz, h1, **{}))
    assert_equal([[h1], {}], o.bfoo(:bar, h1, **{}))
    assert_equal([h1], o.bfoo(:baz, h1, **{}))
    assert_equal([[h1], {}], o.store_foo(:bar, h1, **{}))
    assert_equal([h1], o.store_foo(:baz, h1, **{}))
    assert_equal([[h1], {}], o.foo_bar(h1, **{}))
    assert_equal([h1], o.foo_baz(h1, **{}))
    assert_equal([[h1], {}], o.foo(:foo, :bar, h1, **{}))
    assert_equal([h1], o.foo(:foo, :baz, h1, **{}))
    assert_equal([[h1], {}], o.foo(:foo_bar, h1, **{}))
    assert_equal([h1], o.foo(:foo_baz, h1, **{}))
    assert_equal([[h1], {}], o.foo_foo_bar(h1, **{}))
    assert_equal([h1], o.foo_foo_baz(h1, **{}))

    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.foo(:bar, 1, h1))
    end
    assert_equal([1, h1], o.foo(:baz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.bfoo(:bar, 1, h1))
    end
    assert_equal([1, h1], o.bfoo(:baz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.store_foo(:bar, 1, h1))
    end
    assert_equal([1, h1], o.store_foo(:baz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.foo_bar(1, h1))
    end
    assert_equal([1, h1], o.foo_baz(1, h1))

    assert_equal([[1, h1, 1], {}], o.foo_mod(:bar, 1, :a=>1))
    assert_equal([1, h1, 1], o.foo_mod(:baz, 1, :a=>1))
    assert_equal([[1, h1, 1], {}], o.foo_bar_mod(1, :a=>1))
    assert_equal([1, h1, 1], o.foo_baz_mod(1, :a=>1))

    assert_equal([[1, h1, 1], {}], o.foo_mod(:bar, 1, **h1))
    assert_equal([1, h1, 1], o.foo_mod(:baz, 1, **h1))
    assert_equal([[1, h1, 1], {}], o.foo_bar_mod(1, **h1))
    assert_equal([1, h1, 1], o.foo_baz_mod(1, **h1))

    assert_equal([[h1, {}, 1], {}], o.foo_mod(:bar, h1, **{}))
    assert_equal([h1, {}, 1], o.foo_mod(:baz, h1, **{}))
    assert_equal([[h1, {}, 1], {}], o.foo_bar_mod(h1, **{}))
    assert_equal([h1, {}, 1], o.foo_baz_mod(h1, **{}))

    assert_equal([[1, h1, 1], {}], o.foo_mod(:bar, 1, h1))
    assert_equal([1, h1, 1], o.foo_mod(:baz, 1, h1))
    assert_equal([[1, h1, 1], {}], o.foo_bar_mod(1, h1))
    assert_equal([1, h1, 1], o.foo_baz_mod(1, h1))

    assert_equal([[1], h1], o.foo(:dbar, 1, :a=>1))
    assert_equal([1, h1], o.foo(:dbaz, 1, :a=>1))
    assert_equal([[1], h1], o.bfoo(:dbar, 1, :a=>1))
    assert_equal([1, h1], o.bfoo(:dbaz, 1, :a=>1))
    assert_equal([[1], h1], o.store_foo(:dbar, 1, :a=>1))
    assert_equal([1, h1], o.store_foo(:dbaz, 1, :a=>1))
    assert_equal([[1], h1], o.foo_dbar(1, :a=>1))
    assert_equal([1, h1], o.foo_dbaz(1, :a=>1))

    assert_equal([[1], h1], o.foo(:dbar, 1, **h1))
    assert_equal([1, h1], o.foo(:dbaz, 1, **h1))
    assert_equal([[1], h1], o.bfoo(:dbar, 1, **h1))
    assert_equal([1, h1], o.bfoo(:dbaz, 1, **h1))
    assert_equal([[1], h1], o.store_foo(:dbar, 1, **h1))
    assert_equal([1, h1], o.store_foo(:dbaz, 1, **h1))
    assert_equal([[1], h1], o.foo_dbar(1, **h1))
    assert_equal([1, h1], o.foo_dbaz(1, **h1))

    assert_equal([[h1], {}], o.foo(:dbar, h1, **{}))
    assert_equal([h1], o.foo(:dbaz, h1, **{}))
    assert_equal([[h1], {}], o.bfoo(:dbar, h1, **{}))
    assert_equal([h1], o.bfoo(:dbaz, h1, **{}))
    assert_equal([[h1], {}], o.store_foo(:dbar, h1, **{}))
    assert_equal([h1], o.store_foo(:dbaz, h1, **{}))
    assert_equal([[h1], {}], o.foo_dbar(h1, **{}))
    assert_equal([h1], o.foo_dbaz(h1, **{}))

    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[1], h1], o.foo(:dbar, 1, h1))
    end
    assert_equal([1, h1], o.foo(:dbaz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[1], h1], o.bfoo(:dbar, 1, h1))
    end
    assert_equal([1, h1], o.bfoo(:dbaz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[1], h1], o.store_foo(:dbar, 1, h1))
    end
    assert_equal([1, h1], o.store_foo(:dbaz, 1, h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method is defined here/m) do
      assert_equal([[1], h1], o.foo_dbar(1, h1))
    end
    assert_equal([1, h1], o.foo_dbaz(1, h1))

    assert_equal([[1], h1], o.block(1, :a=>1))
    assert_equal([[1], h1], o.block(1, **h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal([[1], h1], o.block(1, h1))
    end
    assert_equal([[h1], {}], o.block(h1, **{}))

    assert_equal([[1], h1], o.cfunc(1, :a=>1))
    assert_equal([[1], h1], o.cfunc(1, **h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_equal([[1], h1], o.cfunc(1, h1))
    end
    assert_equal([[h1], {}], o.cfunc(h1, **{}))

    o = mmkw.new
    assert_equal([[:b, 1], h1], o.b(1, :a=>1))
    assert_equal([[:b, 1], h1], o.b(1, **h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([[:b, 1], h1], o.b(1, h1))
    end
    assert_equal([[:b, h1], {}], o.b(h1, **{}))

    o = mmnokw.new
    assert_equal([:b, 1, h1], o.b(1, :a=>1))
    assert_equal([:b, 1, h1], o.b(1, **h1))
    assert_equal([:b, 1, h1], o.b(1, h1))
    assert_equal([:b, h1], o.b(h1, **{}))

    o = implicit_super.new
    assert_equal([[1], h1], o.bar(1, :a=>1))
    assert_equal([[1], h1], o.bar(1, **h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.bar(1, h1))
    end
    assert_equal([[h1], {}], o.bar(h1, **{}))

    assert_equal([1, h1], o.baz(1, :a=>1))
    assert_equal([1, h1], o.baz(1, **h1))
    assert_equal([1, h1], o.baz(1, h1))
    assert_equal([h1], o.baz(h1, **{}))

    o = explicit_super.new
    assert_equal([[1], h1], o.bar(1, :a=>1))
    assert_equal([[1], h1], o.bar(1, **h1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.bar(1, h1))
    end
    assert_equal([[h1], {}], o.bar(h1, **{}))

    assert_equal([1, h1], o.baz(1, :a=>1))
    assert_equal([1, h1], o.baz(1, **h1))
    assert_equal([1, h1], o.baz(1, h1))
    assert_equal([h1], o.baz(h1, **{}))

    c.class_eval do
      remove_method(:bar)
      def bar(*args, **kw)
        [args, kw]
      end
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `bar'/m) do
      assert_equal([[1], h1], o.foo(:pass_bar, 1, :a=>1))
    end

    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `initialize'/m) do
      assert_equal([[1], h1], o.foo(:pass_cfunc, 1, :a=>1))
    end

    assert_warn(/Skipping set of ruby2_keywords flag for bar \(method accepts keywords or method does not accept argument splat\)/) do
      assert_nil(c.send(:ruby2_keywords, :bar))
    end

    o = Object.new
    class << o
      alias bar p
    end
    assert_warn(/Skipping set of ruby2_keywords flag for bar \(method not defined in Ruby\)/) do
      assert_nil(o.singleton_class.send(:ruby2_keywords, :bar))
    end
    sc = Class.new(c)
    assert_warn(/Skipping set of ruby2_keywords flag for bar \(can only set in method defining module\)/) do
      sc.send(:ruby2_keywords, :bar)
    end
    m = Module.new
    assert_warn(/Skipping set of ruby2_keywords flag for system \(can only set in method defining module\)/) do
      m.send(:ruby2_keywords, :system)
    end

    assert_raise(NameError) { c.send(:ruby2_keywords, "a5e36ccec4f5080a1d5e63f8") }
    assert_raise(NameError) { c.send(:ruby2_keywords, :quux) }

    c.freeze
    assert_raise(FrozenError) { c.send(:ruby2_keywords, :baz) }
  end

  def test_top_ruby2_keywords
    assert_in_out_err([], <<-INPUT, ["[1, 2, 3]", "{:k=>1}"], [])
      def bar(*a, **kw)
        p a, kw
      end
      ruby2_keywords def foo(*a)
        bar(*a)
      end
      foo(1, 2, 3, k:1)
    INPUT
  end

  def test_dig_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.dig(*args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal([h], [c].dig(0, **h))
    assert_equal([h], [c].dig(0, a: 1))
    assert_equal([h2], [c].dig(0, **h2))
    assert_equal([h3], [c].dig(0, **h3))
    assert_equal([h3], [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:dig)
    def c.dig; end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_raise(ArgumentError) { [c].dig(0, **h) }
    assert_raise(ArgumentError) { [c].dig(0, a: 1) }
    assert_raise(ArgumentError) { [c].dig(0, **h2) }
    assert_raise(ArgumentError) { [c].dig(0, **h3) }
    assert_raise(ArgumentError) { [c].dig(0, a: 1, **h2) }

    c.singleton_class.remove_method(:dig)
    def c.dig(args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal(kw, [c].dig(0, kw, **kw))
    assert_equal(h, [c].dig(0, **h))
    assert_equal(h, [c].dig(0, a: 1))
    assert_equal(h2, [c].dig(0, **h2))
    assert_equal(h3, [c].dig(0, **h3))
    assert_equal(h3, [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:dig)
    def c.dig(**args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal(h, [c].dig(0, **h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal(h, [c].dig(0, a: 1))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_raise(ArgumentError) { [c].dig(0, **h3) }
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_raise(ArgumentError) { [c].dig(0, a: 1, **h2) }
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal(h, [c].dig(0, h))
    end
    assert_raise(ArgumentError) { [c].dig(0, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_raise(ArgumentError) { [c].dig(0, h3) }
    end

    c.singleton_class.remove_method(:dig)
    def c.dig(arg, **args)
      [arg, args]
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal([h, kw], [c].dig(0, **h))
    assert_equal([h, kw], [c].dig(0, a: 1))
    assert_equal([h2, kw], [c].dig(0, **h2))
    assert_equal([h3, kw], [c].dig(0, **h3))
    assert_equal([h3, kw], [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:dig)
    def c.dig(arg=1, **args)
      [arg, args]
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([1, h], [c].dig(0, **h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([1, h], [c].dig(0, a: 1))
    end
    assert_equal([h2, kw], [c].dig(0, **h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([h2, h], [c].dig(0, **h3))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([h2, h], [c].dig(0, a: 1, **h2))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([1, h], [c].dig(0, h))
    end
    assert_equal([h2, kw], [c].dig(0, h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `dig'/m) do
      assert_equal([h2, h], [c].dig(0, h3))
    end
    assert_equal([h, kw], [c].dig(0, h, **{}))
    assert_equal([h2, kw], [c].dig(0, h2, **{}))
    assert_equal([h3, kw], [c].dig(0, h3, **{}))
  end

  def test_dig_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.method_missing(_, *args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal([h], [c].dig(0, **h))
    assert_equal([h], [c].dig(0, a: 1))
    assert_equal([h2], [c].dig(0, **h2))
    assert_equal([h3], [c].dig(0, **h3))
    assert_equal([h3], [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing; end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_raise(ArgumentError) { [c].dig(0, **h) }
    assert_raise(ArgumentError) { [c].dig(0, a: 1) }
    assert_raise(ArgumentError) { [c].dig(0, **h2) }
    assert_raise(ArgumentError) { [c].dig(0, **h3) }
    assert_raise(ArgumentError) { [c].dig(0, a: 1, **h2) }

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal(kw, [c].dig(0, kw, **kw))
    assert_equal(h, [c].dig(0, **h))
    assert_equal(h, [c].dig(0, a: 1))
    assert_equal(h2, [c].dig(0, **h2))
    assert_equal(h3, [c].dig(0, **h3))
    assert_equal(h3, [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal(h, [c].dig(0, **h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal(h, [c].dig(0, a: 1))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_raise(ArgumentError) { [c].dig(0, **h3) }
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_raise(ArgumentError) { [c].dig(0, a: 1, **h2) }
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal(h, [c].dig(0, h))
    end
    assert_raise(ArgumentError) { [c].dig(0, h2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_raise(ArgumentError) { [c].dig(0, h3) }
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg, **args)
      [arg, args]
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_equal([h, kw], [c].dig(0, **h))
    assert_equal([h, kw], [c].dig(0, a: 1))
    assert_equal([h2, kw], [c].dig(0, **h2))
    assert_equal([h3, kw], [c].dig(0, **h3))
    assert_equal([h3, kw], [c].dig(0, a: 1, **h2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal(c, [c].dig(0, **{}))
    assert_equal(c, [c].dig(0, **kw))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([1, h], [c].dig(0, **h))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([1, h], [c].dig(0, a: 1))
    end
    assert_equal([h2, kw], [c].dig(0, **h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, h], [c].dig(0, **h3))
    end
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, h], [c].dig(0, a: 1, **h2))
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([1, h], [c].dig(0, h))
    end
    assert_equal([h2, kw], [c].dig(0, h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, h], [c].dig(0, h3))
    end
    assert_equal([h, kw], [c].dig(0, h, **{}))
    assert_equal([h2, kw], [c].dig(0, h2, **{}))
    assert_equal([h3, kw], [c].dig(0, h3, **{}))
  end

  def test_enumerator_size_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    c.to_enum(:each){|*args| args}.size
    m = ->(*args){ args }
    assert_equal([], c.to_enum(:each, **{}, &m).size)
    assert_equal([], c.to_enum(:each, **kw, &m).size)
    assert_equal([h], c.to_enum(:each, **h, &m).size)
    assert_equal([h], c.to_enum(:each, a: 1, &m).size)
    assert_equal([h2], c.to_enum(:each, **h2, &m).size)
    assert_equal([h3], c.to_enum(:each, **h3, &m).size)
    assert_equal([h3], c.to_enum(:each, a: 1, **h2, &m).size)

    m = ->(){  }
    assert_nil(c.to_enum(:each, **{}, &m).size)
    assert_nil(c.to_enum(:each, **kw, &m).size)
    assert_raise(ArgumentError) { c.to_enum(:each, **h, &m).size }
    assert_raise(ArgumentError) { c.to_enum(:each, a: 1, &m).size }
    assert_raise(ArgumentError) { c.to_enum(:each, **h2, &m).size }
    assert_raise(ArgumentError) { c.to_enum(:each, **h3, &m).size }
    assert_raise(ArgumentError) { c.to_enum(:each, a: 1, **h2, &m).size }

    m = ->(args){ args }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, c.to_enum(:each, **{}, &m).size)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal(kw, c.to_enum(:each, **kw, &m).size)
    end
    assert_equal(kw, c.to_enum(:each, kw, **kw, &m).size)
    assert_equal(h, c.to_enum(:each, **h, &m).size)
    assert_equal(h, c.to_enum(:each, a: 1, &m).size)
    assert_equal(h2, c.to_enum(:each, **h2, &m).size)
    assert_equal(h3, c.to_enum(:each, **h3, &m).size)
    assert_equal(h3, c.to_enum(:each, a: 1, **h2, &m).size)

    m = ->(**args){ args }
    assert_equal(kw, c.to_enum(:each, **{}, &m).size)
    assert_equal(kw, c.to_enum(:each, **kw, &m).size)
    assert_equal(h, c.to_enum(:each, **h, &m).size)
    assert_equal(h, c.to_enum(:each, a: 1, &m).size)
    assert_equal(h2, c.to_enum(:each, **h2, &m).size)
    assert_equal(h3, c.to_enum(:each, **h3, &m).size)
    assert_equal(h3, c.to_enum(:each, a: 1, **h2, &m).size)
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal(h, c.to_enum(:each, h, &m).size)
    end
    assert_raise(ArgumentError) { c.to_enum(:each, h2, &m).size }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/m) do
      assert_raise(ArgumentError) { c.to_enum(:each, h3, &m).size }
    end

    m = ->(arg, **args){ [arg, args] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      c.to_enum(:each, **{}, &m).size
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      c.to_enum(:each, **kw, &m).size
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], c.to_enum(:each, **h, &m).size)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h, kw], c.to_enum(:each, a: 1, &m).size)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h2, kw], c.to_enum(:each, **h2, &m).size)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], c.to_enum(:each, **h3, &m).size)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/m) do
      assert_equal([h3, kw], c.to_enum(:each, a: 1, **h2, &m).size)
    end
    assert_equal([h, kw], c.to_enum(:each, h, &m).size)
    assert_equal([h2, kw], c.to_enum(:each, h2, &m).size)
    assert_equal([h3, kw], c.to_enum(:each, h3, &m).size)

    m = ->(arg=1, **args){ [arg, args] }
    assert_equal([1, kw], c.to_enum(:each, **{}, &m).size)
    assert_equal([1, kw], c.to_enum(:each, **kw, &m).size)
    assert_equal([1, h], c.to_enum(:each, **h, &m).size)
    assert_equal([1, h], c.to_enum(:each, a: 1, &m).size)
    assert_equal([1, h2], c.to_enum(:each, **h2, &m).size)
    assert_equal([1, h3], c.to_enum(:each, **h3, &m).size)
    assert_equal([1, h3], c.to_enum(:each, a: 1, **h2, &m).size)
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal([1, h], c.to_enum(:each, h, &m).size)
    end
    assert_equal([h2, kw], c.to_enum(:each, h2, &m).size)
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/m) do
      assert_equal([h2, h], c.to_enum(:each, h3, &m).size)
    end
  end

  def test_instance_exec_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    m = ->(*args) { args }
    assert_equal([], c.instance_exec(**{}, &m))
    assert_equal([], c.instance_exec(**kw, &m))
    assert_equal([h], c.instance_exec(**h, &m))
    assert_equal([h], c.instance_exec(a: 1, &m))
    assert_equal([h2], c.instance_exec(**h2, &m))
    assert_equal([h3], c.instance_exec(**h3, &m))
    assert_equal([h3], c.instance_exec(a: 1, **h2, &m))

    m = ->() { nil }
    assert_nil(c.instance_exec(**{}, &m))
    assert_nil(c.instance_exec(**kw, &m))
    assert_raise(ArgumentError) { c.instance_exec(**h, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h2, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h3, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, **h2, &m) }

    m = ->(args) { args }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**{}, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**kw, &m))
    end
    assert_equal(kw, c.instance_exec(kw, **kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))

    m = ->(**args) { args }
    assert_equal(kw, c.instance_exec(**{}, &m))
    assert_equal(kw, c.instance_exec(**kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/) do
      assert_equal(h, c.instance_exec(h, &m))
    end
    assert_raise(ArgumentError) { c.instance_exec(h2, &m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_raise(ArgumentError) { c.instance_exec(h3, &m) }
    end

    m = ->(arg, **args) { [arg, args] }
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**{}, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**kw, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(**h, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(a: 1, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, kw], c.instance_exec(**h2, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(**h3, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(a: 1, **h2, &m))
    end
    assert_equal([h, kw], c.instance_exec(h, &m))
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_equal([h3, kw], c.instance_exec(h3, &m))

    m = ->(arg=1, **args) { [arg, args] }
    assert_equal([1, kw], c.instance_exec(**{}, &m))
    assert_equal([1, kw], c.instance_exec(**kw, &m))
    assert_equal([1, h], c.instance_exec(**h, &m))
    assert_equal([1, h], c.instance_exec(a: 1, &m))
    assert_equal([1, h2], c.instance_exec(**h2, &m))
    assert_equal([1, h3], c.instance_exec(**h3, &m))
    assert_equal([1, h3], c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal([1, h], c.instance_exec(h, &m))
    end
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/m) do
      assert_equal([h2, h], c.instance_exec(h3, &m))
    end
  end

  def test_instance_exec_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    m  = c.method(:m)
    assert_equal([], c.instance_exec(**{}, &m))
    assert_equal([], c.instance_exec(**kw, &m))
    assert_equal([h], c.instance_exec(**h, &m))
    assert_equal([h], c.instance_exec(a: 1, &m))
    assert_equal([h2], c.instance_exec(**h2, &m))
    assert_equal([h3], c.instance_exec(**h3, &m))
    assert_equal([h3], c.instance_exec(a: 1, **h2, &m))

    c.singleton_class.remove_method(:m)
    def c.m
    end
    m  = c.method(:m)
    assert_nil(c.instance_exec(**{}, &m))
    assert_nil(c.instance_exec(**kw, &m))
    assert_raise(ArgumentError) { c.instance_exec(**h, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h2, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h3, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, **h2, &m) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    m  = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**{}, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**kw, &m))
    end
    assert_equal(kw, c.instance_exec(kw, **kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    m  = c.method(:m)
    assert_equal(kw, c.instance_exec(**{}, &m))
    assert_equal(kw, c.instance_exec(**kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/) do
      assert_equal(h, c.instance_exec(h, &m))
    end
    assert_raise(ArgumentError) { c.instance_exec(h2, &m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_raise(ArgumentError) { c.instance_exec(h3, &m) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    m  = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**{}, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**kw, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(**h, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(a: 1, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, kw], c.instance_exec(**h2, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(**h3, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(a: 1, **h2, &m))
    end
    assert_equal([h, kw], c.instance_exec(h, &m))
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_equal([h3, kw], c.instance_exec(h3, &m))

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    m  = c.method(:m)
    assert_equal([1, kw], c.instance_exec(**{}, &m))
    assert_equal([1, kw], c.instance_exec(**kw, &m))
    assert_equal([1, h], c.instance_exec(**h, &m))
    assert_equal([1, h], c.instance_exec(a: 1, &m))
    assert_equal([1, h2], c.instance_exec(**h2, &m))
    assert_equal([1, h3], c.instance_exec(**h3, &m))
    assert_equal([1, h3], c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal([1, h], c.instance_exec(h, &m))
    end
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_equal([h2, h], c.instance_exec(h3, &m))
    end
  end

  def test_instance_exec_define_method_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    c.define_singleton_method(:m) do |*args|
      args
    end
    m  = c.method(:m)
    assert_equal([], c.instance_exec(**{}, &m))
    assert_equal([], c.instance_exec(**kw, &m))
    assert_equal([h], c.instance_exec(**h, &m))
    assert_equal([h], c.instance_exec(a: 1, &m))
    assert_equal([h2], c.instance_exec(**h2, &m))
    assert_equal([h3], c.instance_exec(**h3, &m))
    assert_equal([h3], c.instance_exec(a: 1, **h2, &m))

    c.singleton_class.remove_method(:m)
    c.define_singleton_method(:m) do
    end
    m  = c.method(:m)
    assert_nil(c.instance_exec(**{}, &m))
    assert_nil(c.instance_exec(**kw, &m))
    assert_raise(ArgumentError) { c.instance_exec(**h, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h2, &m) }
    assert_raise(ArgumentError) { c.instance_exec(**h3, &m) }
    assert_raise(ArgumentError) { c.instance_exec(a: 1, **h2, &m) }

    c.singleton_class.remove_method(:m)
    c.define_singleton_method(:m) do |args|
      args
    end
    m  = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**{}, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(**kw, &m))
    end
    assert_equal(kw, c.instance_exec(kw, **kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))

    c.singleton_class.remove_method(:m)
    c.define_singleton_method(:m) do |**args|
      args
    end
    m  = c.method(:m)
    assert_equal(kw, c.instance_exec(**{}, &m))
    assert_equal(kw, c.instance_exec(**kw, &m))
    assert_equal(h, c.instance_exec(**h, &m))
    assert_equal(h, c.instance_exec(a: 1, &m))
    assert_equal(h2, c.instance_exec(**h2, &m))
    assert_equal(h3, c.instance_exec(**h3, &m))
    assert_equal(h3, c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/) do
      assert_equal(h, c.instance_exec(h, &m))
    end
    assert_raise(ArgumentError) { c.instance_exec(h2, &m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_raise(ArgumentError) { c.instance_exec(h3, &m) }
    end

    c.singleton_class.remove_method(:m)
    c.define_singleton_method(:m) do |arg, **args|
      [arg, args]
    end
    m  = c.method(:m)
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**{}, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(**kw, &m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(**h, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(a: 1, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, kw], c.instance_exec(**h2, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(**h3, &m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(a: 1, **h2, &m))
    end
    assert_equal([h, kw], c.instance_exec(h, &m))
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_equal([h3, kw], c.instance_exec(h3, &m))

    c.singleton_class.remove_method(:m)
    c.define_singleton_method(:m) do |arg=1, **args|
      [arg, args]
    end
    m  = c.method(:m)
    assert_equal([1, kw], c.instance_exec(**{}, &m))
    assert_equal([1, kw], c.instance_exec(**kw, &m))
    assert_equal([1, h], c.instance_exec(**h, &m))
    assert_equal([1, h], c.instance_exec(a: 1, &m))
    assert_equal([1, h2], c.instance_exec(**h2, &m))
    assert_equal([1, h3], c.instance_exec(**h3, &m))
    assert_equal([1, h3], c.instance_exec(a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal([1, h], c.instance_exec(h, &m))
    end
    assert_equal([h2, kw], c.instance_exec(h2, &m))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_equal([h2, h], c.instance_exec(h3, &m))
    end
  end

  def test_instance_exec_sym_proc_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    def c.m(*args)
      args
    end
    assert_equal([], c.instance_exec(c, **{}, &:m))
    assert_equal([], c.instance_exec(c, **kw, &:m))
    assert_equal([h], c.instance_exec(c, **h, &:m))
    assert_equal([h], c.instance_exec(c, a: 1, &:m))
    assert_equal([h2], c.instance_exec(c, **h2, &:m))
    assert_equal([h3], c.instance_exec(c, **h3, &:m))
    assert_equal([h3], c.instance_exec(c, a: 1, **h2, &:m))

    c.singleton_class.remove_method(:m)
    def c.m
    end
    assert_nil(c.instance_exec(c, **{}, &:m))
    assert_nil(c.instance_exec(c, **kw, &:m))
    assert_raise(ArgumentError) { c.instance_exec(c, **h, &:m) }
    assert_raise(ArgumentError) { c.instance_exec(c, a: 1, &:m) }
    assert_raise(ArgumentError) { c.instance_exec(c, **h2, &:m) }
    assert_raise(ArgumentError) { c.instance_exec(c, **h3, &:m) }
    assert_raise(ArgumentError) { c.instance_exec(c, a: 1, **h2, &:m) }

    c.singleton_class.remove_method(:m)
    def c.m(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(c, **{}, &:m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal(kw, c.instance_exec(c, **kw, &:m))
    end
    assert_equal(kw, c.instance_exec(c, kw, **kw, &:m))
    assert_equal(h, c.instance_exec(c, **h, &:m))
    assert_equal(h, c.instance_exec(c, a: 1, &:m))
    assert_equal(h2, c.instance_exec(c, **h2, &:m))
    assert_equal(h3, c.instance_exec(c, **h3, &:m))
    assert_equal(h3, c.instance_exec(c, a: 1, **h2, &:m))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.instance_exec(c, **{}, &:m))
    assert_equal(kw, c.instance_exec(c, **kw, &:m))
    assert_equal(h, c.instance_exec(c, **h, &:m))
    assert_equal(h, c.instance_exec(c, a: 1, &:m))
    assert_equal(h2, c.instance_exec(c, **h2, &:m))
    assert_equal(h3, c.instance_exec(c, **h3, &:m))
    assert_equal(h3, c.instance_exec(c, a: 1, **h2, &:m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/) do
      assert_equal(h, c.instance_exec(c, h, &:m))
    end
    assert_raise(ArgumentError) { c.instance_exec(c, h2, &:m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_raise(ArgumentError) { c.instance_exec(c, h3, &:m) }
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(c, **{}, &:m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      c.instance_exec(c, **kw, &:m)
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(c, **h, &:m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h, kw], c.instance_exec(c, a: 1, &:m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h2, kw], c.instance_exec(c, **h2, &:m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(c, **h3, &:m))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated/) do
      assert_equal([h3, kw], c.instance_exec(c, a: 1, **h2, &:m))
    end
    assert_equal([h, kw], c.instance_exec(c, h, &:m))
    assert_equal([h2, kw], c.instance_exec(c, h2, &:m))
    assert_equal([h3, kw], c.instance_exec(c, h3, &:m))

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.instance_exec(c, **{}, &:m))
    assert_equal([1, kw], c.instance_exec(c, **kw, &:m))
    assert_equal([1, h], c.instance_exec(c, **h, &:m))
    assert_equal([1, h], c.instance_exec(c, a: 1, &:m))
    assert_equal([1, h2], c.instance_exec(c, **h2, &:m))
    assert_equal([1, h3], c.instance_exec(c, **h3, &:m))
    assert_equal([1, h3], c.instance_exec(c, a: 1, **h2, &:m))
    assert_warn(/Using the last argument as keyword parameters is deprecated/m) do
      assert_equal([1, h], c.instance_exec(c, h, &:m))
    end
    assert_equal([h2, kw], c.instance_exec(c, h2, &:m))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated/) do
      assert_equal([h2, h], c.instance_exec(c, h3, &:m))
    end
  end

  def test_rb_yield_block_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = Object.new
    c.extend Bug::Iter::Yield
    class << c
      alias m yield_block
    end
    def c.c(*args)
      args
    end
    assert_equal([], c.m(:c, **{}))
    assert_equal([], c.m(:c, **kw))
    assert_equal([h], c.m(:c, **h))
    assert_equal([h], c.m(:c, a: 1))
    assert_equal([h2], c.m(:c, **h2))
    assert_equal([h3], c.m(:c, **h3))
    assert_equal([h3], c.m(:c, a: 1, **h2))

    c.singleton_class.remove_method(:c)
    def c.c; end
    assert_nil(c.m(:c, **{}))
    assert_nil(c.m(:c, **kw))
    assert_raise(ArgumentError) { c.m(:c, **h) }
    assert_raise(ArgumentError) { c.m(:c, a: 1) }
    assert_raise(ArgumentError) { c.m(:c, **h2) }
    assert_raise(ArgumentError) { c.m(:c, **h3) }
    assert_raise(ArgumentError) { c.m(:c, a: 1, **h2) }

    c.singleton_class.remove_method(:c)
    def c.c(args)
      args
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal(kw, c.m(:c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal(kw, c.m(:c, **kw))
    end
    assert_equal(kw, c.m(:c, kw, **kw))
    assert_equal(h, c.m(:c, **h))
    assert_equal(h, c.m(:c, a: 1))
    assert_equal(h2, c.m(:c, **h2))
    assert_equal(h3, c.m(:c, **h3))
    assert_equal(h3, c.m(:c, a: 1, **h2))

    c.singleton_class.remove_method(:c)
    def c.c(**args)
      [args, yield(**args)]
    end
    m = ->(**args){ args }
    assert_equal([kw, kw], c.m(:c, **{}, &m))
    assert_equal([kw, kw], c.m(:c, **kw, &m))
    assert_equal([h, h], c.m(:c, **h, &m))
    assert_equal([h, h], c.m(:c, a: 1, &m))
    assert_equal([h2, h2], c.m(:c, **h2, &m))
    assert_equal([h3, h3], c.m(:c, **h3, &m))
    assert_equal([h3, h3], c.m(:c, a: 1, **h2, &m))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `c'/m) do
      assert_equal([h, h], c.m(:c, h, &m))
    end
    assert_raise(ArgumentError) { c.m(:c, h2, &m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `c'/m) do
      assert_raise(ArgumentError) { c.m(:c, h3, &m) }
    end

    c.singleton_class.remove_method(:c)
    def c.c(arg, **args)
      [arg, args]
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([kw, kw], c.m(:c, **{}))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([kw, kw], c.m(:c, **kw))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([h, kw], c.m(:c, **h))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([h, kw], c.m(:c, a: 1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([h2, kw], c.m(:c, **h2))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([h3, kw], c.m(:c, **h3))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `c'/m) do
      assert_equal([h3, kw], c.m(:c, a: 1, **h2))
    end
    assert_equal([h, kw], c.m(:c, h))
    assert_equal([h2, kw], c.m(:c, h2))
    assert_equal([h3, kw], c.m(:c, h3))

    c.singleton_class.remove_method(:c)
    def c.c(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.m(:c, **{}))
    assert_equal([1, kw], c.m(:c, **kw))
    assert_equal([1, h], c.m(:c, **h))
    assert_equal([1, h], c.m(:c, a: 1))
    assert_equal([1, h2], c.m(:c, **h2))
    assert_equal([1, h3], c.m(:c, **h3))
    assert_equal([1, h3], c.m(:c, a: 1, **h2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `c'/m) do
      assert_equal([1, h], c.m(:c, h))
    end
    assert_equal([h2, kw], c.m(:c, h2))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `c'/m) do
      assert_equal([h2, h], c.m(:c, h3))
    end
  end

  def p1
    Proc.new do |str: "foo", num: 424242|
      [str, num]
    end
  end

  def test_p1
    assert_equal(["foo", 424242], p1[])
    assert_equal(["bar", 424242], p1[str: "bar"])
    assert_equal(["foo", 111111], p1[num: 111111])
    assert_equal(["bar", 111111], p1[str: "bar", num: 111111])
    assert_raise(ArgumentError) { p1[str: "bar", check: true] }
    assert_equal(["foo", 424242], p1["string"] )
  end


  def p2
    Proc.new do |x, str: "foo", num: 424242|
      [x, str, num]
    end
  end

  def test_p2
    assert_equal([nil, "foo", 424242], p2[])
    assert_equal([:xyz, "foo", 424242], p2[:xyz])
  end


  def p3
    Proc.new do |str: "foo", num: 424242, **h|
      [str, num, h]
    end
  end

  def test_p3
    assert_equal(["foo", 424242, {}], p3[])
    assert_equal(["bar", 424242, {}], p3[str: "bar"])
    assert_equal(["foo", 111111, {}], p3[num: 111111])
    assert_equal(["bar", 111111, {}], p3[str: "bar", num: 111111])
    assert_equal(["bar", 424242, {:check=>true}], p3[str: "bar", check: true])
    assert_equal(["foo", 424242, {}], p3["string"])
  end


  def p4
    Proc.new do |str: "foo", num: 424242, **h, &blk|
      [str, num, h, blk]
    end
  end

  def test_p4
    assert_equal(["foo", 424242, {}, nil], p4[])
    assert_equal(["bar", 424242, {}, nil], p4[str: "bar"])
    assert_equal(["foo", 111111, {}, nil], p4[num: 111111])
    assert_equal(["bar", 111111, {}, nil], p4[str: "bar", num: 111111])
    assert_equal(["bar", 424242, {:check=>true}, nil], p4[str: "bar", check: true])
    a = p4.call {|x| x + 42 }
    assert_equal(["foo", 424242, {}], a[0, 3])
    assert_equal(43, a.last.call(1))
  end


  def p5
    Proc.new do |*r, str: "foo", num: 424242, **h|
      [r, str, num, h]
    end
  end

  def test_p5
    assert_equal([[], "foo", 424242, {}], p5[])
    assert_equal([[], "bar", 424242, {}], p5[str: "bar"])
    assert_equal([[], "foo", 111111, {}], p5[num: 111111])
    assert_equal([[], "bar", 111111, {}], p5[str: "bar", num: 111111])
    assert_equal([[1], "foo", 424242, {}], p5[1])
    assert_equal([[1, 2], "foo", 424242, {}], p5[1, 2])
    assert_equal([[1, 2, 3], "foo", 424242, {}], p5[1, 2, 3])
    assert_equal([[1], "bar", 424242, {}], p5[1, str: "bar"])
    assert_equal([[1, 2], "bar", 424242, {}], p5[1, 2, str: "bar"])
    assert_equal([[1, 2, 3], "bar", 424242, {}], p5[1, 2, 3, str: "bar"])
  end


  def p6
    Proc.new do |o1, o2=42, *args, p, k: :key, **kw, &b|
      [o1, o2, args, p, k, kw, b]
    end
  end

  def test_p6
    assert_equal([nil, 42, [], nil, :key, {}, nil], p6[])
    assert_equal([1, 42, [], 2, :key, {}, nil], p6[1, 2])
    assert_equal([1, 2, [], 3, :key, {}, nil], p6[1, 2, 3])
    assert_equal([1, 2, [3], 4, :key, {}, nil], p6[1, 2, 3, 4])
    assert_equal([1, 2, [3, 4], 5, :key, {str: "bar"}, nil], p6[1, 2, 3, 4, 5, str: "bar"])
  end

  def test_proc_parameters
    assert_equal([[:key, :str], [:key, :num]], p1.parameters);
    assert_equal([[:opt, :x], [:key, :str], [:key, :num]], p2.parameters);
    assert_equal([[:key, :str], [:key, :num], [:keyrest, :h]], p3.parameters);
    assert_equal([[:key, :str], [:key, :num], [:keyrest, :h], [:block, :blk]], p4.parameters);
    assert_equal([[:rest, :r], [:key, :str], [:key, :num], [:keyrest, :h]], p5.parameters);
    assert_equal([[:opt, :o1], [:opt, :o2], [:rest, :args], [:opt, :p], [:key, :k],
                  [:keyrest, :kw], [:block, :b]], p6.parameters)
  end

  def m1(*args, **options)
    yield(*args, **options)
  end

  def test_block
    blk = Proc.new {|str: "foo", num: 424242| [str, num] }
    assert_equal(["foo", 424242], m1(&blk))
    assert_equal(["bar", 424242], m1(str: "bar", &blk))
    assert_equal(["foo", 111111], m1(num: 111111, &blk))
    assert_equal(["bar", 111111], m1(str: "bar", num: 111111, &blk))
  end

  def rest_keyrest(*args, **opt)
    return *args, opt
  end

  def test_rest_keyrest
    bug7665 = '[ruby-core:51278]'
    bug8463 = '[ruby-core:55203] [Bug #8463]'
    expect = [*%w[foo bar], {zzz: 42}]
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `rest_keyrest'/m) do
      assert_equal(expect, rest_keyrest(*expect), bug7665)
    end
    pr = proc {|*args, **opt| next *args, opt}
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(expect, pr.call(*expect), bug7665)
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(expect, pr.call(expect), bug8463)
    end
    pr = proc {|a, *b, **opt| next a, *b, opt}
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(expect, pr.call(expect), bug8463)
    end
    pr = proc {|a, **opt| next a, opt}
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(expect.values_at(0, -1), pr.call(expect), bug8463)
    end
  end

  def req_plus_keyword(x, **h)
    [x, h]
  end

  def opt_plus_keyword(x=1, **h)
    [x, h]
  end

  def splat_plus_keyword(*a, **h)
    [a, h]
  end

  def test_keyword_split
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `req_plus_keyword'/m) do
      assert_equal([{:a=>1}, {}], req_plus_keyword(:a=>1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `req_plus_keyword'/m) do
      assert_equal([{"a"=>1}, {}], req_plus_keyword("a"=>1))
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `req_plus_keyword'/m) do
      assert_equal([{"a"=>1, :a=>1}, {}], req_plus_keyword("a"=>1, :a=>1))
    end
    assert_equal([{:a=>1}, {}], req_plus_keyword({:a=>1}))
    assert_equal([{"a"=>1}, {}], req_plus_keyword({"a"=>1}))
    assert_equal([{"a"=>1, :a=>1}, {}], req_plus_keyword({"a"=>1, :a=>1}))

    assert_equal([1, {:a=>1}], opt_plus_keyword(:a=>1))
    assert_equal([1, {"a"=>1}], opt_plus_keyword("a"=>1))
    assert_equal([1, {"a"=>1, :a=>1}], opt_plus_keyword("a"=>1, :a=>1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `opt_plus_keyword'/m) do
      assert_equal([1, {:a=>1}], opt_plus_keyword({:a=>1}))
    end
    assert_equal([{"a"=>1}, {}], opt_plus_keyword({"a"=>1}))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `opt_plus_keyword'/m) do
      assert_equal([{"a"=>1}, {:a=>1}], opt_plus_keyword({"a"=>1, :a=>1}))
    end

    assert_equal([[], {:a=>1}], splat_plus_keyword(:a=>1))
    assert_equal([[], {"a"=>1}], splat_plus_keyword("a"=>1))
    assert_equal([[], {"a"=>1, :a=>1}], splat_plus_keyword("a"=>1, :a=>1))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `splat_plus_keyword'/m) do
      assert_equal([[], {:a=>1}], splat_plus_keyword({:a=>1}))
    end
    assert_equal([[{"a"=>1}], {}], splat_plus_keyword({"a"=>1}))
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `splat_plus_keyword'/m) do
      assert_equal([[{"a"=>1}], {:a=>1}], splat_plus_keyword({"a"=>1, :a=>1}))
    end
  end

  def test_bare_kwrest
    # valid syntax, but its semantics is undefined
    assert_valid_syntax("def bug7662(**) end")
    assert_valid_syntax("def bug7662(*, **) end")
    assert_valid_syntax("def bug7662(a, **) end")
  end

  def test_without_paren
    bug7942 = '[ruby-core:52820] [Bug #7942]'
    assert_valid_syntax("def bug7942 a: 1; end")
    assert_valid_syntax("def bug7942 a: 1, **; end")

    o = Object.new
    eval("def o.bug7942 a: 1; a; end", nil, __FILE__, __LINE__)
    assert_equal(1, o.bug7942(), bug7942)
    assert_equal(42, o.bug7942(a: 42), bug7942)

    o = Object.new
    eval("def o.bug7942 a: 1, **; a; end", nil, __FILE__, __LINE__)
    assert_equal(1, o.bug7942(), bug7942)
    assert_equal(42, o.bug7942(a: 42), bug7942)
  end

  def test_required_keyword
    feature7701 = '[ruby-core:51454] [Feature #7701] required keyword argument'
    o = Object.new
    assert_nothing_raised(SyntaxError, feature7701) do
      eval("def o.foo(a:) a; end", nil, "xyzzy")
      eval("def o.bar(a:,**b) [a, b]; end")
    end
    assert_raise_with_message(ArgumentError, /missing keyword/, feature7701) {o.foo}
    assert_raise_with_message(ArgumentError, /unknown keyword/, feature7701) {o.foo(a:0, b:1)}
    begin
      o.foo(a: 0, b: 1)
    rescue => e
      assert_equal('xyzzy', e.backtrace_locations[0].path)
    end
    assert_equal(42, o.foo(a: 42), feature7701)
    assert_equal([[:keyreq, :a]], o.method(:foo).parameters, feature7701)

    bug8139 = '[ruby-core:53608] [Bug #8139] required keyword argument with rest hash'
    assert_equal([42, {}], o.bar(a: 42), feature7701)
    assert_equal([42, {c: feature7701}], o.bar(a: 42, c: feature7701), feature7701)
    assert_equal([[:keyreq, :a], [:keyrest, :b]], o.method(:bar).parameters, feature7701)
    assert_raise_with_message(ArgumentError, /missing keyword/, bug8139) {o.bar(c: bug8139)}
    assert_raise_with_message(ArgumentError, /missing keyword/, bug8139) {o.bar}
  end

  def test_required_keyword_with_newline
    bug9669 = '[ruby-core:61658] [Bug #9669]'
    assert_nothing_raised(SyntaxError, bug9669) do
      eval(<<-'end;', nil, __FILE__, __LINE__)
        def bug9669.foo a:
          return a
        end
      end;
    end
    assert_equal(42, bug9669.foo(a: 42))
    o = nil
    assert_nothing_raised(SyntaxError, bug9669) do
      eval(<<-'end;', nil, __FILE__, __LINE__)
        o = {
          a:
          1
        }
      end;
    end
    assert_equal({a: 1}, o, bug9669)
  end

  def test_required_keyword_with_reserved
    bug10279 = '[ruby-core:65211] [Bug #10279]'
    h = nil
    assert_nothing_raised(SyntaxError, bug10279) do
      break eval(<<-'end;', nil, __FILE__, __LINE__)
        h = {a: if true then 42 end}
      end;
    end
    assert_equal({a: 42}, h, bug10279)
  end

  def test_block_required_keyword
    feature7701 = '[ruby-core:51454] [Feature #7701] required keyword argument'
    b = assert_nothing_raised(SyntaxError, feature7701) do
      break eval("proc {|a:| a}", nil, 'xyzzy', __LINE__)
    end
    assert_raise_with_message(ArgumentError, /missing keyword/, feature7701) {b.call}
    e = assert_raise_with_message(ArgumentError, /unknown keyword/, feature7701) {b.call(a:0, b:1)}
    assert_equal('xyzzy', e.backtrace_locations[0].path)

    assert_equal(42, b.call(a: 42), feature7701)
    assert_equal([[:keyreq, :a]], b.parameters, feature7701)

    bug8139 = '[ruby-core:53608] [Bug #8139] required keyword argument with rest hash'
    b = assert_nothing_raised(SyntaxError, feature7701) do
      break eval("proc {|a:, **bl| [a, bl]}", nil, __FILE__, __LINE__)
    end
    assert_equal([42, {}], b.call(a: 42), feature7701)
    assert_equal([42, {c: feature7701}], b.call(a: 42, c: feature7701), feature7701)
    assert_equal([[:keyreq, :a], [:keyrest, :bl]], b.parameters, feature7701)
    assert_raise_with_message(ArgumentError, /missing keyword/, bug8139) {b.call(c: bug8139)}
    assert_raise_with_message(ArgumentError, /missing keyword/, bug8139) {b.call}

    b = assert_nothing_raised(SyntaxError, feature7701) do
      break eval("proc {|m, a:| [m, a]}", nil, 'xyzzy', __LINE__)
    end
    assert_raise_with_message(ArgumentError, /missing keyword/) {b.call}
    assert_equal([:ok, 42], b.call(:ok, a: 42))
    e = assert_raise_with_message(ArgumentError, /unknown keyword/) {b.call(42, a:0, b:1)}
    assert_equal('xyzzy', e.backtrace_locations[0].path)
    assert_equal([[:opt, :m], [:keyreq, :a]], b.parameters)
  end

  def test_super_with_keyword
    bug8236 = '[ruby-core:54094] [Bug #8236]'
    base = Class.new do
      def foo(*args)
        args
      end
    end
    a = Class.new(base) do
      def foo(arg, bar: 'x')
        super
      end
    end
    b = Class.new(base) do
      def foo(*args, bar: 'x')
        super
      end
    end
    assert_equal([42, {:bar=>"x"}], a.new.foo(42), bug8236)
    assert_equal([42, {:bar=>"x"}], b.new.foo(42), bug8236)
  end

  def test_zsuper_only_named_kwrest
    bug8416 = '[ruby-core:55033] [Bug #8416]'
    base = Class.new do
      def foo(**h)
        h
      end
    end
    a = Class.new(base) do
      def foo(**h)
        super
      end
    end
    assert_equal({:bar=>"x"}, a.new.foo(bar: "x"), bug8416)
  end

  def test_zsuper_only_anonymous_kwrest
    bug8416 = '[ruby-core:55033] [Bug #8416]'
    base = Class.new do
      def foo(**h)
        h
      end
    end
    a = Class.new(base) do
      def foo(**)
        super
      end
    end
    assert_equal({:bar=>"x"}, a.new.foo(bar: "x"), bug8416)
  end

  def test_precedence_of_keyword_arguments
    bug8040 = '[ruby-core:53199] [Bug #8040]'
    a = Class.new do
      def foo(x, **h)
        [x, h]
      end
    end
    assert_equal([{}, {}], a.new.foo({}))
    assert_equal([{}, {:bar=>"x"}], a.new.foo({}, bar: "x"), bug8040)
  end

  def test_precedence_of_keyword_arguments_with_post_argument
    bug8993 = '[ruby-core:57706] [Bug #8993]'
    a = Class.new do
      def foo(a, b, c=1, *d, e, f:2, **g)
        [a, b, c, d, e, f, g]
      end
    end
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `foo'/m) do
      assert_equal([1, 2, 1, [], {:f=>5}, 2, {}], a.new.foo(1, 2, f:5), bug8993)
    end
  end

  def test_splat_keyword_nondestructive
    bug9776 = '[ruby-core:62161] [Bug #9776]'

    h = {a: 1}
    assert_equal({a:1, b:2}, {**h, b:2})
    assert_equal({a:1}, h, bug9776)

    pr = proc {|**opt| next opt}
    assert_equal({a: 1}, pr.call(**h))
    assert_equal({a: 1, b: 2}, pr.call(**h, b: 2))
    assert_equal({a: 1}, h, bug9776)
  end

  def test_splat_hash_conversion
    bug9898 = '[ruby-core:62921] [Bug #9898]'

    o = Object.new
    def o.to_hash() { a: 1 } end
    assert_equal({a: 1}, m1(**o) {|x| break x}, bug9898)
    o2 = Object.new
    def o2.to_hash() { b: 2 } end
    assert_equal({a: 1, b: 2}, m1(**o, **o2) {|x| break x}, bug9898)
  end

  def test_implicit_hash_conversion
    bug10016 = '[ruby-core:63593] [Bug #10016]'

    o = Object.new
    def o.to_hash() { k: 9 } end
    assert_equal([1, 42, [], o, :key, {}, nil], f9(1, o))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m1'/m) do
      assert_equal([1, 9], m1(1, o) {|a, k: 0| break [a, k]}, bug10016)
    end
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `m1'/m) do
      assert_equal([1, 9], m1(1, o, &->(a, k: 0) {break [a, k]}), bug10016)
    end
  end

  def test_splat_hash
    m = Object.new
    def m.f() :ok; end
    def m.f1(a) a; end
    def m.f2(a = nil) a; end
    def m.f3(**a) a; end
    def m.f4(*a) a; end
    o = {a: 1}
    assert_raise_with_message(ArgumentError, /unknown keyword: :a/) {
      m.f(**o)
    }
    o = {}
    assert_equal(:ok, m.f(**o), '[ruby-core:68124] [Bug #10856]')
    a = []
    assert_equal(:ok, m.f(*a, **o), '[ruby-core:83638] [Bug #10856]')
    assert_equal(:OK, m.f1(*a, :OK, **o), '[ruby-core:91825] [Bug #10856]')
    assert_equal({}, m.f1(*a, o), '[ruby-core:91825] [Bug #10856]')

    o = {a: 42}
    assert_warning('', 'splat to mandatory') do
      assert_equal({a: 42}, m.f1(**o))
    end
    assert_warning('') do
      assert_equal({a: 42}, m.f2(**o), '[ruby-core:82280] [Bug #13791]')
    end
    assert_warning('', 'splat to kwrest') do
      assert_equal({a: 42}, m.f3(**o))
    end
    assert_warning('', 'splat to rest') do
      assert_equal([{a: 42}], m.f4(**o))
    end

    assert_warning('') do
      assert_equal({a: 42}, m.f2("a".to_sym => 42), '[ruby-core:82291] [Bug #13793]')
    end

    o = {}
    a = [:ok]
    assert_equal(:ok, m.f2(*a, **o), '[ruby-core:83638] [Bug #10856]')
  end

  def test_gced_object_in_stack
    bug8964 = '[ruby-dev:47729] [Bug #8964]'
    assert_normal_exit %q{
      def m(a: [])
      end
      GC.stress = true
      tap { m }
      GC.start
      tap { m }
    }, bug8964
    assert_normal_exit %q{
      prc = Proc.new {|a: []|}
      GC.stress = true
      tap { prc.call }
      GC.start
      tap { prc.call }
    }, bug8964
  end

  def test_dynamic_symbol_keyword
    bug10266 = '[ruby-dev:48564] [Bug #10266]'
    assert_separately(['-', bug10266], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      bug = ARGV.shift
      "hoge".to_sym
      assert_nothing_raised(bug) {eval("def a(hoge:); end")}
    end;
  end

  def test_unknown_keyword_with_block
    bug10413 = '[ruby-core:65837] [Bug #10413]'
    class << (o = Object.new)
      def bar(k2: 'v2')
      end

      def foo
        bar(k1: 1)
      end
    end
    assert_raise_with_message(ArgumentError, /unknown keyword: :k1/, bug10413) {
      o.foo {raise "unreachable"}
    }
  end

  def test_unknown_keyword
    bug13004 = '[ruby-dev:49893] [Bug #13004]'
    assert_raise_with_message(ArgumentError, /unknown keyword: :"invalid-argument"/, bug13004) {
      [].sample(random: nil, "invalid-argument": nil)
    }
  end

  def test_super_with_anon_restkeywords
    bug10659 = '[ruby-core:67157] [Bug #10659]'

    foo = Class.new do
      def foo(**h)
        h
      end
    end

    class << (obj = foo.new)
      def foo(bar: "bar", **)
        super
      end
    end

    assert_nothing_raised(TypeError, bug10659) {
      assert_equal({:bar => "bar"}, obj.foo, bug10659)
    }
  end

  def m(a) yield a end

  def test_nonsymbol_key
    result = m(["a" => 10]) { |a = nil, **b| [a, b] }
    assert_equal([{"a" => 10}, {}], result)
  end

  def method_for_test_to_hash_call_during_setup_complex_parameters k1:, k2:, **rest_kw
    [k1, k2, rest_kw]
  end

  def test_to_hash_call_during_setup_complex_parameters
    sym = "sym_#{Time.now}".to_sym
    h = method_for_test_to_hash_call_during_setup_complex_parameters k1: "foo", k2: "bar", sym => "baz"
    assert_equal ["foo", "bar", {sym => "baz"}], h, '[Bug #11027]'
  end

  class AttrSetTest
    attr_accessor :foo
    alias set_foo :foo=
  end

  def test_attr_set_method_cache
    obj = AttrSetTest.new
    h = {a: 1, b: 2}
    2.times{
      obj.foo = 1
      assert_equal(1, obj.foo)
      obj.set_foo 2
      assert_equal(2, obj.foo)
      obj.set_foo(x: 1, y: 2)
      assert_equal({x: 1, y: 2}, obj.foo)
      obj.set_foo(x: 1, y: 2, **h)
      assert_equal({x: 1, y: 2, **h}, obj.foo)
    }
  end

  def test_kwrest_overwritten
    bug13015 = '[ruby-core:78536] [Bug #13015]'

    klass = EnvUtil.labeled_class("Parent") do
      def initialize(d:)
      end
    end

    klass = EnvUtil.labeled_class("Child", klass) do
      def initialize(d:, **h)
        h = [2, 3]
        super
      end
    end

    assert_raise_with_message(TypeError, /expected Hash/, bug13015) do
      klass.new(d: 4)
    end
  end

  def test_non_keyword_hash_subclass
    bug12884 = '[ruby-core:77813] [Bug #12884]'
    klass = EnvUtil.labeled_class("Child", Hash)
    obj = Object.new
    def obj.t(params = klass.new, d: nil); params; end
    x = klass.new
    x["foo"] = "bar"
    result = obj.t(x)
    assert_equal(x, result)
    assert_kind_of(klass, result, bug12884)
  end

  def test_arity_error_message
    obj = Object.new
    def obj.t(x:) end
    assert_raise_with_message(ArgumentError, /required keyword: x\)/) do
      obj.t(42)
    end
    obj = Object.new
    def obj.t(x:, y:, z: nil) end
    assert_raise_with_message(ArgumentError, /required keywords: x, y\)/) do
      obj.t(42)
    end
  end

  def many_kwargs(a0: '', a1: '', a2: '', a3: '', a4: '', a5: '', a6: '', a7: '',
                  b0: '', b1: '', b2: '', b3: '', b4: '', b5: '', b6: '', b7: '',
                  c0: '', c1: '', c2: '', c3: '', c4: '', c5: '', c6: '', c7: '',
                  d0: '', d1: '', d2: '', d3: '', d4: '', d5: '', d6: '', d7: '',
                  e0: '')
    [a0, a1, a2, a3, a4, a5, a6, a7,
     b0, b1, b2, b3, b4, b5, b6, b7,
     c0, c1, c2, c3, c4, c5, c6, c7,
     d0, d1, d2, d3, d4, d5, d6, d7,
     e0]
  end

  def test_many_kwargs
    i = 0
    assert_equal(:ok, many_kwargs(a0: :ok)[i], "#{i}: a0"); i+=1
    assert_equal(:ok, many_kwargs(a1: :ok)[i], "#{i}: a1"); i+=1
    assert_equal(:ok, many_kwargs(a2: :ok)[i], "#{i}: a2"); i+=1
    assert_equal(:ok, many_kwargs(a3: :ok)[i], "#{i}: a3"); i+=1
    assert_equal(:ok, many_kwargs(a4: :ok)[i], "#{i}: a4"); i+=1
    assert_equal(:ok, many_kwargs(a5: :ok)[i], "#{i}: a5"); i+=1
    assert_equal(:ok, many_kwargs(a6: :ok)[i], "#{i}: a6"); i+=1
    assert_equal(:ok, many_kwargs(a7: :ok)[i], "#{i}: a7"); i+=1

    assert_equal(:ok, many_kwargs(b0: :ok)[i], "#{i}: b0"); i+=1
    assert_equal(:ok, many_kwargs(b1: :ok)[i], "#{i}: b1"); i+=1
    assert_equal(:ok, many_kwargs(b2: :ok)[i], "#{i}: b2"); i+=1
    assert_equal(:ok, many_kwargs(b3: :ok)[i], "#{i}: b3"); i+=1
    assert_equal(:ok, many_kwargs(b4: :ok)[i], "#{i}: b4"); i+=1
    assert_equal(:ok, many_kwargs(b5: :ok)[i], "#{i}: b5"); i+=1
    assert_equal(:ok, many_kwargs(b6: :ok)[i], "#{i}: b6"); i+=1
    assert_equal(:ok, many_kwargs(b7: :ok)[i], "#{i}: b7"); i+=1

    assert_equal(:ok, many_kwargs(c0: :ok)[i], "#{i}: c0"); i+=1
    assert_equal(:ok, many_kwargs(c1: :ok)[i], "#{i}: c1"); i+=1
    assert_equal(:ok, many_kwargs(c2: :ok)[i], "#{i}: c2"); i+=1
    assert_equal(:ok, many_kwargs(c3: :ok)[i], "#{i}: c3"); i+=1
    assert_equal(:ok, many_kwargs(c4: :ok)[i], "#{i}: c4"); i+=1
    assert_equal(:ok, many_kwargs(c5: :ok)[i], "#{i}: c5"); i+=1
    assert_equal(:ok, many_kwargs(c6: :ok)[i], "#{i}: c6"); i+=1
    assert_equal(:ok, many_kwargs(c7: :ok)[i], "#{i}: c7"); i+=1

    assert_equal(:ok, many_kwargs(d0: :ok)[i], "#{i}: d0"); i+=1
    assert_equal(:ok, many_kwargs(d1: :ok)[i], "#{i}: d1"); i+=1
    assert_equal(:ok, many_kwargs(d2: :ok)[i], "#{i}: d2"); i+=1
    assert_equal(:ok, many_kwargs(d3: :ok)[i], "#{i}: d3"); i+=1
    assert_equal(:ok, many_kwargs(d4: :ok)[i], "#{i}: d4"); i+=1
    assert_equal(:ok, many_kwargs(d5: :ok)[i], "#{i}: d5"); i+=1
    assert_equal(:ok, many_kwargs(d6: :ok)[i], "#{i}: d6"); i+=1
    assert_equal(:ok, many_kwargs(d7: :ok)[i], "#{i}: d7"); i+=1

    assert_equal(:ok, many_kwargs(e0: :ok)[i], "#{i}: e0"); i+=1
  end

  def test_splat_empty_hash_with_block_passing
    assert_valid_syntax("bug15087(**{}, &nil)")
  end

  def test_do_not_use_newarraykwsplat
    assert_equal([42, "foo", 424242], f2(*[], 42, **{}))
    a = [1, 2, 3]
    assert_equal([[1,2,3,4,5,6], "foo", 424242, {:k=>:k}], f7(*a, 4,5,6, k: :k))
  end
end

class TestKeywordArgumentsSymProcRefinements < Test::Unit::TestCase
  class C
    def call(*args, **kw)
      yield(self, *args, **kw)
    end
  end
  using(Module.new do
    refine C do
      def m(*args, **kw)
        super
      end
    end
  end)

  def test_sym_proc_refine_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = C.new
    def c.m(*args)
      args
    end
    assert_equal([], c.call(**{}, &:m))
    assert_equal([], c.call(**kw, &:m))
    assert_equal([h], c.call(**h, &:m))
    assert_equal([h], c.call(h, **{}, &:m))
    assert_equal([h], c.call(a: 1, &:m))
    assert_equal([h2], c.call(**h2, &:m))
    assert_equal([h3], c.call(**h3, &:m))
    assert_equal([h3], c.call(a: 1, **h2, &:m))

    c.singleton_class.remove_method(:m)
    def c.m; end
    assert_nil(c.call(**{}, &:m))
    assert_nil(c.call(**kw, &:m))
    assert_raise(ArgumentError) { c.call(**h, &:m) }
    assert_raise(ArgumentError) { c.call(a: 1, &:m) }
    assert_raise(ArgumentError) { c.call(**h2, &:m) }
    assert_raise(ArgumentError) { c.call(**h3, &:m) }
    assert_raise(ArgumentError) { c.call(a: 1, **h2, &:m) }

    redef = -> do
      c.singleton_class.remove_method(:m)
      eval <<-END
        def c.m(args)
          args
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.call(**{}, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal(kw, c.call(**kw, &:m))
    end
    assert_equal(h, c.call(**h, &:m))
    assert_equal(h, c.call(a: 1, &:m))
    assert_equal(h2, c.call(**h2, &:m))
    assert_equal(h3, c.call(**h3, &:m))
    assert_equal(h3, c.call(a: 1, **h2, &:m))

    c.singleton_class.remove_method(:m)
    def c.m(**args)
      args
    end
    assert_equal(kw, c.call(**{}, &:m))
    assert_equal(kw, c.call(**kw, &:m))
    assert_equal(h, c.call(**h, &:m))
    assert_equal(h, c.call(a: 1, &:m))
    assert_equal(h2, c.call(**h2, &:m))
    assert_equal(h3, c.call(**h3, &:m))
    assert_equal(h3, c.call(a: 1, **h2, &:m))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(h, c.call(h, &:m))
    end
    assert_raise(ArgumentError) { c.call(h2, &:m) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `call'/m) do
      assert_raise(ArgumentError) { c.call(h3, &:m) }
    end

    redef = -> do
      c.singleton_class.remove_method(:m)
      eval <<-END
        def c.m(arg, **args)
          [arg, args]
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], c.call(**{}, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([kw, kw], c.call(**kw, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.call(**h, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h, kw], c.call(a: 1, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h2, kw], c.call(**h2, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.call(**h3, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `m'/m) do
      assert_equal([h3, kw], c.call(a: 1, **h2, &:m))
    end

    c.singleton_class.remove_method(:m)
    def c.m(arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.call(**{}, &:m))
    assert_equal([1, kw], c.call(**kw, &:m))
    assert_equal([1, h], c.call(**h, &:m))
    assert_equal([1, h], c.call(a: 1, &:m))
    assert_equal([1, h2], c.call(**h2, &:m))
    assert_equal([1, h3], c.call(**h3, &:m))
    assert_equal([1, h3], c.call(a: 1, **h2, &:m))
  end

  def test_sym_proc_refine_super_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = C.new
    def c.method_missing(_, *args)
      args
    end
    assert_equal([], c.call(**{}, &:m))
    assert_equal([], c.call(**kw, &:m))
    assert_equal([h], c.call(**h, &:m))
    assert_equal([h], c.call(h, **{}, &:m))
    assert_equal([h], c.call(a: 1, &:m))
    assert_equal([h2], c.call(**h2, &:m))
    assert_equal([h3], c.call(**h3, &:m))
    assert_equal([h3], c.call(a: 1, **h2, &:m))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_) end
    assert_nil(c.call(**{}, &:m))
    assert_nil(c.call(**kw, &:m))
    assert_raise(ArgumentError) { c.call(**h, &:m) }
    assert_raise(ArgumentError) { c.call(a: 1, &:m) }
    assert_raise(ArgumentError) { c.call(**h2, &:m) }
    assert_raise(ArgumentError) { c.call(**h3, &:m) }
    assert_raise(ArgumentError) { c.call(a: 1, **h2, &:m) }

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, args)
          args
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.call(**{}, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.call(**kw, &:m))
    end
    assert_equal(h, c.call(**h, &:m))
    assert_equal(h, c.call(a: 1, &:m))
    assert_equal(h2, c.call(**h2, &:m))
    assert_equal(h3, c.call(**h3, &:m))
    assert_equal(h3, c.call(a: 1, **h2, &:m))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(kw, c.call(**{}, &:m))
    assert_equal(kw, c.call(**kw, &:m))
    assert_equal(h, c.call(**h, &:m))
    assert_equal(h, c.call(a: 1, &:m))
    assert_equal(h2, c.call(**h2, &:m))
    assert_equal(h3, c.call(**h3, &:m))
    assert_equal(h3, c.call(a: 1, **h2, &:m))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(h, c.call(h, &:m2))
    end
    assert_raise(ArgumentError) { c.call(h2, &:m2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `call'/m) do
      assert_raise(ArgumentError) { c.call(h3, &:m2) }
    end

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, arg, **args)
          [arg, args]
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.call(**{}, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.call(**kw, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.call(**h, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.call(a: 1, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, kw], c.call(**h2, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.call(**h3, &:m))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.call(a: 1, **h2, &:m))
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.call(**{}, &:m))
    assert_equal([1, kw], c.call(**kw, &:m))
    assert_equal([1, h], c.call(**h, &:m))
    assert_equal([1, h], c.call(a: 1, &:m))
    assert_equal([1, h2], c.call(**h2, &:m))
    assert_equal([1, h3], c.call(**h3, &:m))
    assert_equal([1, h3], c.call(a: 1, **h2, &:m))
  end

  def test_sym_proc_refine_method_missing_kwsplat
    kw = {}
    h = {:a=>1}
    h2 = {'a'=>1}
    h3 = {'a'=>1, :a=>1}

    c = C.new
    def c.method_missing(_, *args)
      args
    end
    assert_equal([], c.call(**{}, &:m2))
    assert_equal([], c.call(**kw, &:m2))
    assert_equal([h], c.call(**h, &:m2))
    assert_equal([h], c.call(h, **{}, &:m2))
    assert_equal([h], c.call(a: 1, &:m2))
    assert_equal([h2], c.call(**h2, &:m2))
    assert_equal([h3], c.call(**h3, &:m2))
    assert_equal([h3], c.call(a: 1, **h2, &:m2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_) end
    assert_nil(c.call(**{}, &:m2))
    assert_nil(c.call(**kw, &:m2))
    assert_raise(ArgumentError) { c.call(**h, &:m2) }
    assert_raise(ArgumentError) { c.call(a: 1, &:m2) }
    assert_raise(ArgumentError) { c.call(**h2, &:m2) }
    assert_raise(ArgumentError) { c.call(**h3, &:m2) }
    assert_raise(ArgumentError) { c.call(a: 1, **h2, &:m2) }

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, args)
          args
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.call(**{}, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal(kw, c.call(**kw, &:m2))
    end
    assert_equal(h, c.call(**h, &:m2))
    assert_equal(h, c.call(a: 1, &:m2))
    assert_equal(h2, c.call(**h2, &:m2))
    assert_equal(h3, c.call(**h3, &:m2))
    assert_equal(h3, c.call(a: 1, **h2, &:m2))

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, **args)
      args
    end
    assert_equal(kw, c.call(**{}, &:m2))
    assert_equal(kw, c.call(**kw, &:m2))
    assert_equal(h, c.call(**h, &:m2))
    assert_equal(h, c.call(a: 1, &:m2))
    assert_equal(h2, c.call(**h2, &:m2))
    assert_equal(h3, c.call(**h3, &:m2))
    assert_equal(h3, c.call(a: 1, **h2, &:m2))
    assert_warn(/Using the last argument as keyword parameters is deprecated.*The called method `call'/m) do
      assert_equal(h, c.call(h, &:m2))
    end
    assert_raise(ArgumentError) { c.call(h2, &:m2) }
    assert_warn(/Splitting the last argument into positional and keyword parameters is deprecated.*The called method `call'/m) do
      assert_raise(ArgumentError) { c.call(h3, &:m2) }
    end

    redef = -> do
      c.singleton_class.remove_method(:method_missing)
      eval <<-END
        def c.method_missing(_, arg, **args)
          [arg, args]
        end
      END
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.call(**{}, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([kw, kw], c.call(**kw, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.call(**h, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h, kw], c.call(a: 1, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h2, kw], c.call(**h2, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.call(**h3, &:m2))
    end
    redef[]
    assert_warn(/Passing the keyword argument as the last hash parameter is deprecated.*The called method `method_missing'/m) do
      assert_equal([h3, kw], c.call(a: 1, **h2, &:m2))
    end

    c.singleton_class.remove_method(:method_missing)
    def c.method_missing(_, arg=1, **args)
      [arg, args]
    end
    assert_equal([1, kw], c.call(**{}, &:m2))
    assert_equal([1, kw], c.call(**kw, &:m2))
    assert_equal([1, h], c.call(**h, &:m2))
    assert_equal([1, h], c.call(a: 1, &:m2))
    assert_equal([1, h2], c.call(**h2, &:m2))
    assert_equal([1, h3], c.call(**h3, &:m2))
    assert_equal([1, h3], c.call(a: 1, **h2, &:m2))
  end

  def test_protected_kwarg
    mock = Class.new do
      def foo
        bar('x', y: 'z')
      end
      protected
      def bar(x, y)
        nil
      end
    end

    assert_nothing_raised do
      mock.new.foo
    end
  end
end
