# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require 'timeout'

module TestStruct
  def test_struct
    struct_test = @Struct.new("Test", :foo, :bar)
    assert_equal(@Struct::Test, struct_test)

    test = struct_test.new(1, 2)
    assert_equal(1, test.foo)
    assert_equal(2, test.bar)
    assert_equal(1, test[0])
    assert_equal(2, test[1])

    a, b = test.to_a
    assert_equal(1, a)
    assert_equal(2, b)

    test[0] = 22
    assert_equal(22, test.foo)

    test.bar = 47
    assert_equal(47, test.bar)

    @Struct.class_eval do
      remove_const :Test
    end
  end

  # [ruby-dev:26247] more than 10 struct members causes segmentation fault
  def test_morethan10members
    list = %w( a b c d  e f g h  i j k l  m n o p )
    until list.empty?
      c = @Struct.new(* list.map {|ch| ch.intern }).new
      list.each do |ch|
        c.__send__(ch)
      end
      list.pop
    end
  end

  def test_larger_than_largest_pool
    count = (GC::INTERNAL_CONSTANTS[:RVARGC_MAX_ALLOCATE_SIZE] / RbConfig::SIZEOF["void*"]) + 1
    list = Array(0..count)
    klass = @Struct.new(*list.map { |i| :"a_#{i}"})
    struct = klass.new(*list)
    assert_equal 0, struct.a_0
  end

  def test_small_structs
    names = [:a, :b, :c, :d]
    1.upto(4) {|n|
      fields = names[0, n]
      klass = @Struct.new(*fields)
      o = klass.new(*(0...n).to_a)
      fields.each_with_index {|name, i|
        assert_equal(i, o[name])
      }
      o = klass.new(*(0...n).to_a.reverse)
      fields.each_with_index {|name, i|
        assert_equal(n-i-1, o[name])
      }
    }
  end

  def test_inherit
    klass = @Struct.new(:a)
    klass2 = Class.new(klass)
    o = klass2.new(1)
    assert_equal(1, o.a)
  end

  def test_attrset_id
    assert_raise(ArgumentError) { Struct.new(:x=) }
  end

  def test_members
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal([:a], klass.members)
    assert_equal([:a], o.members)
  end

  def test_ref
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal(1, o[:a])
    assert_raise(NameError) { o[:b] }
  end

  def test_set
    klass = @Struct.new(:a)
    o = klass.new(1)
    o[:a] = 2
    assert_equal(2, o[:a])
    assert_raise(NameError) { o[:b] = 3 }
  end

  def test_struct_new
    assert_raise(NameError) { @Struct.new("foo") }
    assert_nothing_raised { @Struct.new("Foo") }
    @Struct.instance_eval { remove_const(:Foo) }
    assert_nothing_raised { @Struct.new(:a) { } }
    assert_raise(RuntimeError) { @Struct.new(:a) { raise } }

    assert_equal([:utime, :stime, :cutime, :cstime], Process.times.members)
  end

  def test_struct_new_with_hash
    assert_raise_with_message(TypeError, /not a symbol/) {Struct.new(:a, {})}
    assert_raise_with_message(TypeError, /not a symbol/) {Struct.new(:a, {name: "b"})}
  end

  def test_struct_new_with_keyword_init
    @Struct.new("KeywordInitTrue", :a, :b, keyword_init: true)
    @Struct.new("KeywordInitFalse", :a, :b, keyword_init: false)

    assert_raise(ArgumentError) { @Struct::KeywordInitTrue.new(1, 2) }
    assert_raise(ArgumentError) { @Struct::KeywordInitTrue.new({a: 100}, 2) }
    assert_nothing_raised { @Struct::KeywordInitFalse.new(1, 2) }
    assert_nothing_raised { @Struct::KeywordInitTrue.new(a: 1, b: 2) }
    assert_raise(ArgumentError) { @Struct::KeywordInitTrue.new(1, b: 2) }
    assert_raise(ArgumentError) { @Struct::KeywordInitTrue.new(a: 1, b: 2, c: 3) }
    assert_equal @Struct::KeywordInitTrue.new(a: 1, b: 2).values, @Struct::KeywordInitFalse.new(1, 2).values
    assert_equal "#{@Struct}::KeywordInitFalse", @Struct::KeywordInitFalse.inspect
    assert_equal "#{@Struct}::KeywordInitTrue(keyword_init: true)", @Struct::KeywordInitTrue.inspect
    # eval is needed to prevent the warning duplication filter
    k = Class.new(@Struct::KeywordInitTrue) {def initialize(b, options); super(a: options, b: b); end}
    o = assert_warn('') { k.new(42, {foo: 1, bar: 2}) }
    assert_equal(1, o.a[:foo])

    @Struct.instance_eval do
      remove_const(:KeywordInitTrue)
      remove_const(:KeywordInitFalse)
    end
  end

  def test_struct_new_with_keyword_init_and_block
    struct = @Struct.new(:a, :b, keyword_init: true) do
      def c
        a + b
      end
    end

    assert_equal(3, struct.new(a: 1, b: 2).c)
  end

  def test_struct_keyword_init_p
    struct = @Struct.new(:a, :b, keyword_init: true)
    assert_equal(true, struct.keyword_init?)

    struct = @Struct.new(:a, :b, keyword_init: false)
    assert_equal(false, struct.keyword_init?)

    struct = @Struct.new(:a, :b)
    assert_nil(struct.keyword_init?)
  end

  def test_initialize
    klass = @Struct.new(:a)
    assert_raise(ArgumentError) { klass.new(1, 2) }
    klass = @Struct.new(:total) do
      def initialize(a, b)
        super(a+b)
      end
    end
    assert_equal 3, klass.new(1,2).total
  end

  def test_initialize_with_kw
    klass = @Struct.new(:foo, :options) do
      def initialize(foo, **options)
        super(foo, options)
      end
    end
    assert_equal({}, klass.new(42, **Hash.new).options)
    x = assert_warn('') { klass.new(1, bar: 2) }
    assert_equal 2, x.options[:bar]
  end

  def test_each
    klass = @Struct.new(:a, :b)
    o = klass.new(1, 2)
    assert_equal([1, 2], o.each.to_a)
  end

  def test_each_pair
    klass = @Struct.new(:a, :b)
    o = klass.new(1, 2)
    assert_equal([[:a, 1], [:b, 2]], o.each_pair.to_a)
    bug7382 = '[ruby-dev:46533]'
    a = []
    o.each_pair {|x| a << x}
    assert_equal([[:a, 1], [:b, 2]], a, bug7382)
  end

  def test_inspect
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal("#<struct a=1>", o.inspect)
    o.a = o
    assert_match(/^#<struct a=#<struct #<.*?>:...>>$/, o.inspect)

    @Struct.new("Foo", :a)
    o = @Struct::Foo.new(1)
    assert_equal("#<struct #@Struct::Foo a=1>", o.inspect)
    @Struct.instance_eval { remove_const(:Foo) }

    klass = @Struct.new(:a, :b)
    o = klass.new(1, 2)
    assert_equal("#<struct a=1, b=2>", o.inspect)

    klass = @Struct.new(:@a)
    o = klass.new(1)
    assert_equal(1, o.__send__(:@a))
    assert_equal("#<struct :@a=1>", o.inspect)
    o.__send__(:"@a=", 2)
    assert_equal(2, o.__send__(:@a))
    assert_equal("#<struct :@a=2>", o.inspect)
    o.__send__("@a=", 3)
    assert_equal(3, o.__send__(:@a))
    assert_equal("#<struct :@a=3>", o.inspect)

    methods = klass.instance_methods(false)
    assert_equal([:@a, :"@a="].sort.inspect, methods.sort.inspect, '[Bug #8756]')
    assert_include(methods, :@a)
    assert_include(methods, :"@a=")
  end

  def test_init_copy
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal(o, o.dup)
  end

  def test_aref
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal(1, o[0])
    assert_raise_with_message(IndexError, /offset -2\b/) {o[-2]}
    assert_raise_with_message(IndexError, /offset 1\b/) {o[1]}
    assert_raise_with_message(NameError, /foo/) {o["foo"]}
    assert_raise_with_message(NameError, /foo/) {o[:foo]}
  end

  def test_aset
    klass = @Struct.new(:a)
    o = klass.new(1)
    o[0] = 2
    assert_equal(2, o[:a])
    assert_raise_with_message(IndexError, /offset -2\b/) {o[-2] = 3}
    assert_raise_with_message(IndexError, /offset 1\b/) {o[1] = 3}
    assert_raise_with_message(NameError, /foo/) {o["foo"] = 3}
    assert_raise_with_message(NameError, /foo/) {o[:foo] = 3}
  end

  def test_values_at
    klass = @Struct.new(:a, :b, :c, :d, :e, :f)
    o = klass.new(1, 2, 3, 4, 5, 6)
    assert_equal([2, 4, 6], o.values_at(1, 3, 5))
    assert_equal([2, 3, 4, 3, 4, 5], o.values_at(1..3, 2...5))
  end

  def test_select
    klass = @Struct.new(:a, :b, :c, :d, :e, :f)
    o = klass.new(1, 2, 3, 4, 5, 6)
    assert_equal([1, 3, 5], o.select {|v| v % 2 != 0 })
    assert_raise(ArgumentError) { o.select(1) }
  end

  def test_filter
    klass = @Struct.new(:a, :b, :c, :d, :e, :f)
    o = klass.new(1, 2, 3, 4, 5, 6)
    assert_equal([1, 3, 5], o.filter {|v| v % 2 != 0 })
    assert_raise(ArgumentError) { o.filter(1) }
  end

  def test_big_struct
    klass1 = @Struct.new(*('a'..'z').map(&:to_sym))
    o = klass1.new
    assert_nil o.z
    assert_equal(:foo, o.z = :foo)
    assert_equal(:foo, o.z)
    assert_equal(:foo, o[25])
  end

  def test_overridden_aset
    bug10601 = '[ruby-core:66846] [Bug #10601]: should not be affected by []= method'

    struct = Class.new(Struct.new(*(:a..:z), :result)) do
      def []=(*args)
        raise args.inspect
      end
    end

    obj = struct.new
    assert_nothing_raised(RuntimeError, bug10601) do
      obj.result = 42
    end
    assert_equal(42, obj.result, bug10601)
  end

  def test_overridden_aref
    bug10601 = '[ruby-core:66846] [Bug #10601]: should not be affected by [] method'

    struct = Class.new(Struct.new(*(:a..:z), :result)) do
      def [](*args)
        raise args.inspect
      end
    end

    obj = struct.new
    obj.result = 42
    result = assert_nothing_raised(RuntimeError, bug10601) do
      break obj.result
    end
    assert_equal(42, result, bug10601)
  end

  def test_equal
    klass1 = @Struct.new(:a)
    klass2 = @Struct.new(:a, :b)
    o1 = klass1.new(1)
    o2 = klass1.new(1)
    o3 = klass2.new(1)
    assert_equal(o1, o2)
    assert_not_equal(o1, o3)
  end

  def test_hash
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_kind_of(Integer, o.hash)
    assert_kind_of(String, o.hash.to_s)
  end

  def test_eql
    klass1 = @Struct.new(:a)
    klass2 = @Struct.new(:a, :b)
    o1 = klass1.new(1)
    o2 = klass1.new(1)
    o3 = klass2.new(1)
    assert_operator(o1, :eql?, o2)
    assert_not_operator(o1, :eql?, o3)
  end

  def test_size
    klass = @Struct.new(:a)
    o = klass.new(1)
    assert_equal(1, o.size)
  end

  def test_error
    assert_raise(TypeError){
      @Struct.new(0)
    }
  end

  def test_redefinition_warning
    @Struct.new(name = "RedefinitionWarning")
    e = EnvUtil.verbose_warning do
      @Struct.new("RedefinitionWarning")
    end
    assert_match(/redefining constant #@Struct::RedefinitionWarning/, e)

    @Struct.class_eval do
      remove_const name
    end
  end

  def test_keyword_args_warning
    assert_warn('') { assert_equal(1, @Struct.new(:a).new(a: 1).a) }
    assert_warn('') { assert_equal(1, @Struct.new(:a, keyword_init: nil).new(a: 1).a) }
    assert_warn('') { assert_equal({a: 1}, @Struct.new(:a).new({a: 1}).a) }
    assert_warn('') { assert_equal({a: 1}, @Struct.new(:a, :b).new(1, a: 1).b) }
    assert_warn('') { assert_equal(1, @Struct.new(:a, keyword_init: true).new(a: 1).a) }
    assert_warn('') { assert_equal({a: 1}, @Struct.new(:a, keyword_init: nil).new({a: 1}).a) }
    assert_warn('') { assert_equal({a: 1}, @Struct.new(:a, keyword_init: false).new(a: 1).a) }
    assert_warn('') { assert_equal({a: 1}, @Struct.new(:a, keyword_init: false).new({a: 1}).a) }
  end

  def test_nonascii
    struct_test = @Struct.new(name = "R\u{e9}sum\u{e9}", :"r\u{e9}sum\u{e9}")
    assert_equal(@Struct.const_get("R\u{e9}sum\u{e9}"), struct_test, '[ruby-core:24849]')
    a = struct_test.new(42)
    assert_equal("#<struct #@Struct::R\u{e9}sum\u{e9} r\u{e9}sum\u{e9}=42>", a.inspect, '[ruby-core:24849]')
    e = EnvUtil.verbose_warning do
      @Struct.new("R\u{e9}sum\u{e9}", :"r\u{e9}sum\u{e9}")
    end
    assert_nothing_raised(Encoding::CompatibilityError) do
      assert_match(/redefining constant #@Struct::R\u{e9}sum\u{e9}/, e)
    end

    @Struct.class_eval do
      remove_const name
    end
  end

  def test_junk
    struct_test = @Struct.new("Foo", "a\000")
    o = struct_test.new(1)
    assert_equal(1, o.send("a\000"))
    @Struct.instance_eval { remove_const(:Foo) }
  end

  def test_comparison_when_recursive
    klass1 = @Struct.new(:a, :b, :c)

    x = klass1.new(1, 2, nil); x.c = x
    y = klass1.new(1, 2, nil); y.c = y
    Timeout.timeout(1) {
      assert_equal x, y
      assert_operator x, :eql?, y
    }

    z = klass1.new(:something, :other, nil); z.c = z
    Timeout.timeout(1) {
      assert_not_equal x, z
      assert_not_operator x, :eql?, z
    }

    x.c = y; y.c = x
    Timeout.timeout(1) {
      assert_equal x, y
      assert_operator x, :eql?, y
    }

    x.c = z; z.c = x
    Timeout.timeout(1) {
      assert_not_equal x, z
      assert_not_operator x, :eql?, z
    }
  end

  def test_to_h
    klass = @Struct.new(:a, :b, :c, :d, :e, :f)
    o = klass.new(1, 2, 3, 4, 5, 6)
    assert_equal({a:1, b:2, c:3, d:4, e:5, f:6}, o.to_h)
  end

  def test_to_h_block
    klass = @Struct.new(:a, :b, :c, :d, :e, :f)
    o = klass.new(1, 2, 3, 4, 5, 6)
    assert_equal({"a" => 1, "b" => 4, "c" => 9, "d" => 16, "e" => 25, "f" => 36},
                 o.to_h {|k, v| [k.to_s, v*v]})
  end

  def test_question_mark_in_member
    klass = @Struct.new(:a, :b?)
    x = Object.new
    o = klass.new("test", x)
    assert_same(x, o.b?)
    o.send("b?=", 42)
    assert_equal(42, o.b?)
  end

  def test_bang_mark_in_member
    klass = @Struct.new(:a, :b!)
    x = Object.new
    o = klass.new("test", x)
    assert_same(x, o.b!)
    o.send("b!=", 42)
    assert_equal(42, o.b!)
  end

  def test_setter_method_returns_value
    klass = @Struct.new(:a)
    x = klass.new
    assert_equal "[Bug #9353]", x.send(:a=, "[Bug #9353]")
  end

  def test_dig
    klass = @Struct.new(:a)
    o = klass.new(klass.new({b: [1, 2, 3]}))
    assert_equal(1, o.dig(:a, :a, :b, 0))
    assert_nil(o.dig(:b, 0))
  end

  def test_new_duplicate
    bug12291 = '[ruby-core:74971] [Bug #12291]'
    assert_raise_with_message(ArgumentError, /duplicate member/, bug12291) {
      @Struct.new(:a, :a)
    }
  end

  def test_deconstruct_keys
    klass = @Struct.new(:a, :b)
    o = klass.new(1, 2)
    assert_equal({a: 1, b: 2}, o.deconstruct_keys(nil))
    assert_equal({a: 1, b: 2}, o.deconstruct_keys([:b, :a]))
    assert_equal({a: 1}, o.deconstruct_keys([:a]))
    assert_not_send([o.deconstruct_keys([:a, :c]), :key?, :c])
    assert_raise(TypeError) {
      o.deconstruct_keys(0)
    }
  end

  def test_public_send
    klass = @Struct.new(:a)
    x = klass.new(1)
    assert_equal(1, x.public_send("a"))
    assert_equal(42, x.public_send("a=", 42))
    assert_equal(42, x.public_send("a"))
  end

  def test_arity
    klass = @Struct.new(:a)
    assert_equal 0, klass.instance_method(:a).arity
    assert_equal 1, klass.instance_method(:a=).arity

    klass.module_eval do
      define_method(:b=, instance_method(:a=))
      alias c= a=
    end

    assert_equal 1, klass.instance_method(:b=).arity
    assert_equal 1, klass.instance_method(:c=).arity
  end

  def test_parameters
    klass = @Struct.new(:a)
    assert_equal [], klass.instance_method(:a).parameters
    # NOTE: :_ may not be a spec.
    assert_equal [[:req, :_]], klass.instance_method(:a=).parameters

    klass.module_eval do
      define_method(:b=, instance_method(:a=))
      alias c= a=
    end

    assert_equal [[:req, :_]], klass.instance_method(:b=).parameters
    assert_equal [[:req, :_]], klass.instance_method(:c=).parameters
  end

  class TopStruct < Test::Unit::TestCase
    include TestStruct

    def initialize(*)
      super
      @Struct = Struct
    end
  end

  class SubStruct < Test::Unit::TestCase
    include TestStruct
    SubStruct = Class.new(Struct)

    def initialize(*)
      super
      @Struct = SubStruct
    end
  end
end
