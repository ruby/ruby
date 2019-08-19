# frozen_string_literal: false
require 'test/unit'

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
    assert_equal([{"bar"=>42}, "foo", 424242], f2("bar"=>42))
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

  def m1(*args)
    yield(*args)
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
    assert_equal(expect, rest_keyrest(*expect), bug7665)
    pr = proc {|*args, **opt| next *args, opt}
    assert_equal(expect, pr.call(*expect), bug7665)
    assert_equal(expect, pr.call(expect), bug8463)
    pr = proc {|a, *b, **opt| next a, *b, opt}
    assert_equal(expect, pr.call(expect), bug8463)
    pr = proc {|a, **opt| next a, opt}
    assert_equal(expect.values_at(0, -1), pr.call(expect), bug8463)
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
    assert_equal([1, 2, 1, [], {:f=>5}, 2, {}], a.new.foo(1, 2, f:5), bug8993)
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
    assert_equal([1, 9], m1(1, o) {|a, k: 0| break [a, k]}, bug10016)
    assert_equal([1, 9], m1(1, o, &->(a, k: 0) {break [a, k]}), bug10016)
  end

  def test_splat_hash
    m = Object.new
    def m.f() :ok; end
    def m.f1(a) a; end
    def m.f2(a = nil) a; end
    def m.f3(**a) a; end
    def m.f4(*a) a; end
    o = {a: 1}
    assert_raise_with_message(ArgumentError, /unknown keyword: a/) {
      m.f(**o)
    }
    o = {}
    assert_equal(:ok, m.f(**o), '[ruby-core:68124] [Bug #10856]')
    a = []
    assert_equal(:ok, m.f(*a, **o), '[ruby-core:83638] [Bug #10856]')

    o = {a: 42}
    assert_warning(/splat keyword/, 'splat to mandatory') do
      assert_equal({a: 42}, m.f1(**o))
    end
    assert_warning(/splat keyword/) do
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
    assert_raise_with_message(ArgumentError, /unknown keyword: k1/, bug10413) {
      o.foo {raise "unreachable"}
    }
  end

  def test_unknown_keyword
    bug13004 = '[ruby-dev:49893] [Bug #13004]'
    assert_raise_with_message(ArgumentError, /unknown keyword: invalid-argument/, bug13004) {
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
end
