# frozen_string_literal: false
require 'test/unit'
require '-test-/iter'

class TestCall < Test::Unit::TestCase
  # These dummy method definitions prevent warnings "the block passed to 'a'..."
  def a(&) = nil
  def b(&) = nil
  def c(&) = nil
  def d(&) = nil
  def e(&) = nil
  def f(&) = nil
  def g(&) = nil
  def h(&) = nil
  def i(&) = nil
  def j(&) = nil
  def k(&) = nil
  def l(&) = nil
  def m(&) = nil
  def n(&) = nil
  def o(&) = nil

  def aaa(a, b=100, *rest, &)
    res = [a, b]
    res += rest if rest
    return res
  end

  def test_call
    assert_raise(ArgumentError) {aaa()}
    assert_raise(ArgumentError) {aaa}

    assert_equal([1, 100], aaa(1))
    assert_equal([1, 2], aaa(1, 2))
    assert_equal([1, 2, 3, 4], aaa(1, 2, 3, 4))
    assert_equal([1, 2, 3, 4], aaa(1, *[2, 3, 4]))
  end

  def test_callinfo
    bug9622 = '[ruby-core:61422] [Bug #9622]'
    o = Class.new do
      def foo(*args)
        bar(:foo, *args)
      end
      def bar(name)
        name
      end
    end.new
    e = assert_raise(ArgumentError) {o.foo(100)}
    assert_nothing_raised(ArgumentError) {o.foo}
    assert_raise_with_message(ArgumentError, e.message, bug9622) {o.foo(100)}
  end

  def test_safe_call
    s = Struct.new(:x, :y, :z)
    o = s.new("x")
    assert_equal("X", o.x&.upcase)
    assert_nil(o.y&.upcase)
    assert_equal("x", o.x)
    o&.x = 6
    assert_equal(6, o.x)
    o&.x *= 7
    assert_equal(42, o.x)
    o&.y = 5
    assert_equal(5, o.y)
    o&.z ||= 6
    assert_equal(6, o.z)
    o&.z &&= 7
    assert_equal(7, o.z)

    o = nil
    assert_nil(o&.x)
    assert_nothing_raised(NoMethodError) {o&.x = raise}
    assert_nothing_raised(NoMethodError) {o&.x = raise; nil}
    assert_nothing_raised(NoMethodError) {o&.x *= raise}
    assert_nothing_raised(NoMethodError) {o&.x *= raise; nil}
    assert_nothing_raised(NoMethodError) {o&.x ||= raise}
    assert_nothing_raised(NoMethodError) {o&.x ||= raise; nil}
    assert_nothing_raised(NoMethodError) {o&.x &&= raise}
    assert_nothing_raised(NoMethodError) {o&.x &&= raise; nil}
  end

  def test_safe_call_evaluate_arguments_only_method_call_is_made
    count = 0
    proc = proc { count += 1; 1 }
    s = Struct.new(:x, :y)
    o = s.new(["a", "b", "c"])

    o.y&.at(proc.call)
    assert_equal(0, count)

    o.x&.at(proc.call)
    assert_equal(1, count)
  end

  def test_safe_call_block_command
    assert_nil(("a".sub! "b" do end&.foo 1))
  end

  def test_safe_call_block_call
    assert_nil(("a".sub! "b" do end&.foo))
  end

  def test_safe_call_block_call_brace
    assert_nil(("a".sub! "b" do end&.foo {}))
    assert_nil(("a".sub! "b" do end&.foo do end))
  end

  def test_safe_call_block_call_command
    assert_nil(("a".sub! "b" do end&.foo 1 do end))
  end

  def test_invalid_safe_call
    h = nil
    assert_raise(NoMethodError) {
      h[:foo] = nil
    }
  end

  def test_frozen_splat_and_keywords
   a = [1, 2].freeze
   def self.f(*a); a end
   assert_equal([1, 2, {kw: 3}], f(*a, kw: 3))
  end

  def test_call_bmethod_proc
    pr = proc{|sym| sym}
    define_singleton_method(:a, &pr)
    ary = [10]
    assert_equal(10, a(*ary))
  end

  def test_call_bmethod_proc_restarg
    pr = proc{|*sym| sym}
    define_singleton_method(:a, &pr)
    ary = [10]
    assert_equal([10], a(*ary))
    assert_equal([10], a(10))
  end

  def test_call_op_asgn_keywords
    h = Class.new do
      attr_reader :get, :set
      def v; yield; [*@get, *@set] end
      def [](*a, **b, &c) @get = [a, b, c]; @set = []; 3 end
      def []=(*a, **b, &c) @set = [a, b, c] end
    end.new

    a = []
    kw = {}
    b = lambda{}

    # Prevent "assigned but unused variable" warnings
    _ = [h, a, kw, b]

    message = /keyword arg given in index assignment/

    # +=, without block, non-popped
    assert_syntax_error(%q{h[**kw] += 1}, message)
    assert_syntax_error(%q{h[0, **kw] += 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw] += 1}, message)
    assert_syntax_error(%q{h[kw: 5] += 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] += 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] += 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] += 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] += 1}, message)

    # +=, with block, non-popped
    assert_syntax_error(%q{h[**kw, &b] += 1}, message)
    assert_syntax_error(%q{h[0, **kw, &b] += 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] += 1}, message)
    assert_syntax_error(%q{h[kw: 5, &b] += 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] += 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] += 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] += 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] += 1}, message)

    # +=, without block, popped
    assert_syntax_error(%q{h[**kw] += 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw] += 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] += 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] += 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] += 1; nil}, message)

    # +=, with block, popped
    assert_syntax_error(%q{h[**kw, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] += 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] += 1; nil}, message)

    # &&=, without block, non-popped
    assert_syntax_error(%q{h[**kw] &&= 1}, message)
    assert_syntax_error(%q{h[0, **kw] &&= 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] &&= 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] &&= 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] &&= 1}, message)

    # &&=, with block, non-popped
    assert_syntax_error(%q{h[**kw, &b] &&= 1}, message)
    assert_syntax_error(%q{h[0, **kw, &b] &&= 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5, &b] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] &&= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] &&= 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] &&= 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] &&= 1}, message)

    # &&=, without block, popped
    assert_syntax_error(%q{h[**kw] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] &&= 1; nil}, message)

    # &&=, with block, popped
    assert_syntax_error(%q{h[**kw, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] &&= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] &&= 1; nil}, message)

    # ||=, without block, non-popped
    assert_syntax_error(%q{h[**kw] ||= 1}, message)
    assert_syntax_error(%q{h[0, **kw] ||= 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] ||= 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] ||= 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] ||= 1}, message)

    # ||=, with block, non-popped
    assert_syntax_error(%q{h[**kw, &b] ||= 1}, message)
    assert_syntax_error(%q{h[0, **kw, &b] ||= 1}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5, &b] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] ||= 1}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] ||= 1}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] ||= 1}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] ||= 1}, message)

    # ||=, without block, popped
    assert_syntax_error(%q{h[**kw] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, nil: 3] ||= 1; nil}, message)

    # ||=, with block, popped
    assert_syntax_error(%q{h[**kw, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, **kw, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, **kw, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[kw: 5, a: 2, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, kw: 5, a: 2, &b] ||= 1; nil}, message)
    assert_syntax_error(%q{h[0, *a, kw: 5, a: 2, b: 3, &b] ||= 1; nil}, message)

  end

  def test_kwsplat_block_order_op_asgn
    o = Object.new
    ary = []
    o.define_singleton_method(:to_a) {ary << :to_a; []}
    o.define_singleton_method(:to_hash) {ary << :to_hash; {}}
    o.define_singleton_method(:to_proc) {ary << :to_proc; lambda{}}

    def o.[](...) 2 end
    def o.[]=(...) end

    message = /keyword arg given in index assignment/

    assert_syntax_error(%q{o[kw: 1] += 1}, message)
    assert_syntax_error(%q{o[**o] += 1}, message)
    assert_syntax_error(%q{o[**o, &o] += 1}, message)
    assert_syntax_error(%q{o[*o, **o, &o] += 1}, message)
  end

  def test_call_op_asgn_keywords_mutable
    h = Class.new do
      attr_reader :get, :set
      def v; yield; [*@get, *@set] end
      def [](*a, **b)
        @get = [a.dup, b.dup]
        a << :splat_modified
        b[:kw_splat_modified] = true
        @set = []
        3
      end
      def []=(*a, **b) @set = [a, b] end
    end.new

    message = /keyword arg given in index assignment/

    a = []
    kw = {}

    # Prevent "assigned but unused variable" warnings
    _ = [h, a, kw]

    assert_syntax_error(%q{h[*a, 2, b: 5, **kw] += 1}, message)
  end

  def test_call_splat_post_order
    bug12860 = '[ruby-core:77701] [Bug# 12860]'
    ary = [1, 2]
    assert_equal([1, 2, 1], aaa(*ary, ary.shift), bug12860)
    ary = [1, 2]
    assert_equal([0, 1, 2, 1], aaa(0, *ary, ary.shift), bug12860)
  end

  def test_call_splat_block_order
    bug16504 = '[ruby-core:96769] [Bug# 16504]'
    b = proc{}
    ary = [1, 2, b]
    assert_equal([1, 2, b], aaa(*ary, &ary.pop), bug16504)
    ary = [1, 2, b]
    assert_equal([0, 1, 2, b], aaa(0, *ary, &ary.pop), bug16504)
  end

  def test_call_splat_kw_order
    b = {}
    ary = [1, 2, b]
    assert_equal([1, 2, b, {a: b}], aaa(*ary, a: ary.pop))
    ary = [1, 2, b]
    assert_equal([0, 1, 2, b, {a: b}], aaa(0, *ary, a: ary.pop))
  end

  def test_call_splat_kw_splat_order
    b = {}
    ary = [1, 2, b]
    assert_equal([1, 2, b], aaa(*ary, **ary.pop))
    ary = [1, 2, b]
    assert_equal([0, 1, 2, b], aaa(0, *ary, **ary.pop))
  end

  def test_call_args_splat_with_nonhash_keyword_splat
    o = Object.new
    def o.to_hash; {a: 1} end
    def self.f(*a, **kw)
      kw
    end
    assert_equal Hash, f(*[], **o).class
  end

  def test_call_args_splat_with_pos_arg_kw_splat_is_not_mutable
    o = Object.new
    def o.foo(a, **h)= h[:splat_modified] = true

    a = []
    b = {splat_modified: false}

    o.foo(*a, :x, **b)

    assert_equal({splat_modified: false}, b)
  end

  UNNECESSARY_POS_SPLAT_MESSAGE = "This method call implicitly allocates a potentially " \
    "unnecessary array for the positional splat, because a keyword, keyword splat, or " \
    "block pass expression could cause an evaluation order issue if an array is not " \
    "allocated for the positional splat\. You can avoid this allocation by assigning " \
    "the related keyword, keyword splat, or block pass expression to a local variable " \
    "and using that local variable."
  def test_unnecessary_positional_splat_alloc_due_to_kw_warning
    assert_in_out_err([], <<-INPUT, %w(), Regexp.new(UNNECESSARY_POS_SPLAT_MESSAGE))
      $VERBOSE = false
      Warning[:performance] = true
      eval(<<-RUBY)
        def self.kw = {}
        def self.x(...) = nil
        a = []
        x(*a, kw:)
      RUBY
    INPUT
  end

  def test_unnecessary_positional_splat_alloc_due_to_kw_splat_warning
    assert_in_out_err([], <<-INPUT, %w(), Regexp.new(UNNECESSARY_POS_SPLAT_MESSAGE))
      $VERBOSE = false
      Warning[:performance] = true
      eval(<<-RUBY)
        def self.kw = {}
        def self.x(...) = nil
        a = []
        x(*a, **kw)
      RUBY
    INPUT
  end

  def test_unnecessary_positional_splat_alloc_due_to_block_warning
    assert_in_out_err([], <<-INPUT, %w(), Regexp.new(UNNECESSARY_POS_SPLAT_MESSAGE))
      $VERBOSE = false
      Warning[:performance] = true
      eval(<<-RUBY)
        def self.kw = {}
        def self.x(...) = nil
        a = []
        x(*a, &kw)
      RUBY
    INPUT
  end

  def test_unnecessary_keyword_splat_alloc_due_to_block_warning
    message = "This method call implicitly allocates a potentially " \
        "unnecessary hash for the keyword splat, because the block pass expression could " \
        "cause an evaluation order issue if a hash is not allocated for the keyword splat. " \
        "You can avoid this allocation by assigning the block pass expression to a local " \
        "variable, and using that local variable."
    assert_in_out_err([], <<-INPUT, %w(), Regexp.new(message));
      $VERBOSE = false
      Warning[:performance] = true
      eval(<<-RUBY)
        def self.kw = {}
        def self.x(...) = nil
        h = {}
        x(**kw, &kw)
      RUBY
    INPUT
  end

  def test_anon_splat
    r2kh = Hash.ruby2_keywords_hash(kw: 2)
    r2kea = [r2kh]
    r2ka = [1, r2kh]

    def self.s(*) ->(*a){a}.call(*) end
    assert_equal([], s)
    assert_equal([1], s(1))
    assert_equal([{kw: 2}], s(kw: 2))
    assert_equal([{kw: 2}], s(**{kw: 2}))
    assert_equal([1, {kw: 2}], s(1, kw: 2))
    assert_equal([1, {kw: 2}], s(1, **{kw: 2}))
    assert_equal([{kw: 2}], s(*r2kea))
    assert_equal([1, {kw: 2}], s(*r2ka))

    singleton_class.remove_method(:s)
    def self.s(*, kw: 0) [*->(*a){a}.call(*), kw] end
    assert_equal([0], s)
    assert_equal([1, 0], s(1))
    assert_equal([2], s(kw: 2))
    assert_equal([2], s(**{kw: 2}))
    assert_equal([1, 2], s(1, kw: 2))
    assert_equal([1, 2], s(1, **{kw: 2}))
    assert_equal([2], s(*r2kea))
    assert_equal([1, 2], s(*r2ka))

    singleton_class.remove_method(:s)
    def self.s(*, **kw) [*->(*a){a}.call(*), kw] end
    assert_equal([{}], s)
    assert_equal([1, {}], s(1))
    assert_equal([{kw: 2}], s(kw: 2))
    assert_equal([{kw: 2}], s(**{kw: 2}))
    assert_equal([1, {kw: 2}], s(1, kw: 2))
    assert_equal([1, {kw: 2}], s(1, **{kw: 2}))
    assert_equal([{kw: 2}], s(*r2kea))
    assert_equal([1, {kw: 2}], s(*r2ka))

    singleton_class.remove_method(:s)
    def self.s(*, kw: 0, **kws) [*->(*a){a}.call(*), kw, kws] end
    assert_equal([0, {}], s)
    assert_equal([1, 0, {}], s(1))
    assert_equal([2, {}], s(kw: 2))
    assert_equal([2, {}], s(**{kw: 2}))
    assert_equal([1, 2, {}], s(1, kw: 2))
    assert_equal([1, 2, {}], s(1, **{kw: 2}))
    assert_equal([2, {}], s(*r2kea))
    assert_equal([1, 2, {}], s(*r2ka))
  end

  def test_kwsplat_block_eval_order
    def self.t(**kw, &b) [kw, b] end

    pr = ->{}
    h = {a: pr}
    a = []

    ary = t(**h, &h.delete(:a))
    assert_equal([{a: pr}, pr], ary)

    h = {a: pr}
    ary = t(*a, **h, &h.delete(:a))
    assert_equal([{a: pr}, pr], ary)
  end

  def test_kwsplat_block_order
    o = Object.new
    ary = []
    o.define_singleton_method(:to_a) {ary << :to_a; []}
    o.define_singleton_method(:to_hash) {ary << :to_hash; {}}
    o.define_singleton_method(:to_proc) {ary << :to_proc; lambda{}}

    def self.t(...) end

    t(**o, &o)
    assert_equal([:to_hash, :to_proc], ary)

    ary.clear
    t(*o, **o, &o)
    assert_equal([:to_a, :to_hash, :to_proc], ary)
  end

  def test_kwsplat_block_order_super
    def self.t(splat)
      o = Object.new
      ary = []
      o.define_singleton_method(:to_a) {ary << :to_a; []}
      o.define_singleton_method(:to_hash) {ary << :to_hash; {}}
      o.define_singleton_method(:to_proc) {ary << :to_proc; lambda{}}
      if splat
        super(*o, **o, &o)
      else
        super(**o, &o)
      end
      ary
    end
    extend Module.new{def t(...) end}

    assert_equal([:to_hash, :to_proc], t(false))
    assert_equal([:to_a, :to_hash, :to_proc], t(true))
  end

  OVER_STACK_LEN = (ENV['RUBY_OVER_STACK_LEN'] || 150).to_i # Greater than VM_ARGC_STACK_MAX
  OVER_STACK_ARGV = OVER_STACK_LEN.times.to_a.freeze

  def test_call_cfunc_splat_large_array_bug_4040
    a = OVER_STACK_ARGV

    assert_equal(a, [].push(*a))
    assert_equal(a, [].push(a[0], *a[1..]))
    assert_equal(a, [].push(a[0], a[1], *a[2..]))
    assert_equal(a, [].push(*a[0..1], *a[2..]))
    assert_equal(a, [].push(*a[...-1], a[-1]))
    assert_equal(a, [].push(a[0], *a[1...-1], a[-1]))
    assert_equal(a, [].push(a[0], a[1], *a[2...-1], a[-1]))
    assert_equal(a, [].push(*a[0..1], *a[2...-1], a[-1]))
    assert_equal(a, [].push(*a[...-2], a[-2], a[-1]))
    assert_equal(a, [].push(a[0], *a[1...-2], a[-2], a[-1]))
    assert_equal(a, [].push(a[0], a[1], *a[2...-2], a[-2], a[-1]))
    assert_equal(a, [].push(*a[0..1], *a[2...-2], a[-2], a[-1]))

    kw = {x: 1}
    a_kw = a + [kw]

    assert_equal(a_kw, [].push(*a, **kw))
    assert_equal(a_kw, [].push(a[0], *a[1..], **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2..], **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2..], **kw))
    assert_equal(a_kw, [].push(*a[...-1], a[-1], **kw))
    assert_equal(a_kw, [].push(a[0], *a[1...-1], a[-1], **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-1], a[-1], **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-1], a[-1], **kw))
    assert_equal(a_kw, [].push(*a[...-2], a[-2], a[-1], **kw))
    assert_equal(a_kw, [].push(a[0], *a[1...-2], a[-2], a[-1], **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-2], a[-2], a[-1], **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-2], a[-2], a[-1], **kw))

    assert_equal(a_kw, [].push(*a, x: 1))
    assert_equal(a_kw, [].push(a[0], *a[1..], x: 1))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2..], x: 1))
    assert_equal(a_kw, [].push(*a[0..1], *a[2..], x: 1))
    assert_equal(a_kw, [].push(*a[...-1], a[-1], x: 1))
    assert_equal(a_kw, [].push(a[0], *a[1...-1], a[-1], x: 1))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-1], a[-1], x: 1))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-1], a[-1], x: 1))
    assert_equal(a_kw, [].push(*a[...-2], a[-2], a[-1], x: 1))
    assert_equal(a_kw, [].push(a[0], *a[1...-2], a[-2], a[-1], x: 1))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-2], a[-2], a[-1], x: 1))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-2], a[-2], a[-1], x: 1))

    a_kw[-1][:y] = 2
    kw = {y: 2}

    assert_equal(a_kw, [].push(*a, x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], *a[1..], x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2..], x: 1, **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2..], x: 1, **kw))
    assert_equal(a_kw, [].push(*a[...-1], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], *a[1...-1], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-1], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-1], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(*a[...-2], a[-2], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], *a[1...-2], a[-2], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(a[0], a[1], *a[2...-2], a[-2], a[-1], x: 1, **kw))
    assert_equal(a_kw, [].push(*a[0..1], *a[2...-2], a[-2], a[-1], x: 1, **kw))

    kw = {}

    assert_equal(a, [].push(*a, **kw))
    assert_equal(a, [].push(a[0], *a[1..], **kw))
    assert_equal(a, [].push(a[0], a[1], *a[2..], **kw))
    assert_equal(a, [].push(*a[0..1], *a[2..], **kw))
    assert_equal(a, [].push(*a[...-1], a[-1], **kw))
    assert_equal(a, [].push(a[0], *a[1...-1], a[-1], **kw))
    assert_equal(a, [].push(a[0], a[1], *a[2...-1], a[-1], **kw))
    assert_equal(a, [].push(*a[0..1], *a[2...-1], a[-1], **kw))
    assert_equal(a, [].push(*a[...-2], a[-2], a[-1], **kw))
    assert_equal(a, [].push(a[0], *a[1...-2], a[-2], a[-1], **kw))
    assert_equal(a, [].push(a[0], a[1], *a[2...-2], a[-2], a[-1], **kw))
    assert_equal(a, [].push(*a[0..1], *a[2...-2], a[-2], a[-1], **kw))

    a_kw = a + [Hash.ruby2_keywords_hash({})]
    assert_equal(a, [].push(*a_kw))

    # Single test with value that would cause SystemStackError.
    # Not all tests use such a large array to reduce testing time.
    assert_equal(1380888, [].push(*1380888.times.to_a).size)
  end

  def test_call_iseq_large_array_splat_fail
    def self.a; end
    def self.b(a=1); end
    def self.c(k: 1); end
    def self.d(**kw); end
    def self.e(k: 1, **kw); end
    def self.f(a=1, k: 1); end
    def self.g(a=1, **kw); end
    def self.h(a=1, k: 1, **kw); end

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        instance_eval("#{meth}(*OVER_STACK_ARGV)", __FILE__, __LINE__)
      end
    end
  end

  def test_call_iseq_large_array_splat_pass
    def self.a(*a); a.length end
    assert_equal OVER_STACK_LEN, a(*OVER_STACK_ARGV)

    def self.b(_, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), b(*OVER_STACK_ARGV)

    def self.c(_, *a, _); a.length end
    assert_equal (OVER_STACK_LEN - 2), c(*OVER_STACK_ARGV)

    def self.d(b=1, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), d(*OVER_STACK_ARGV)

    def self.e(b=1, *a, _); a.length end
    assert_equal (OVER_STACK_LEN - 2), e(*OVER_STACK_ARGV)

    def self.f(b, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), f(*OVER_STACK_ARGV)

    def self.g(*a, k: 1); a.length end
    assert_equal OVER_STACK_LEN, g(*OVER_STACK_ARGV)

    def self.h(*a, **kw); a.length end
    assert_equal OVER_STACK_LEN, h(*OVER_STACK_ARGV)

    def self.i(*a, k: 1, **kw); a.length end
    assert_equal OVER_STACK_LEN, i(*OVER_STACK_ARGV)

    def self.j(b=1, *a, k: 1); a.length end
    assert_equal (OVER_STACK_LEN - 1), j(*OVER_STACK_ARGV)

    def self.k(b=1, *a, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 1), k(*OVER_STACK_ARGV)

    def self.l(b=1, *a, k: 1, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 1), l(*OVER_STACK_ARGV)

    def self.m(b=1, *a, _, k: 1); a.length end
    assert_equal (OVER_STACK_LEN - 2), m(*OVER_STACK_ARGV)

    def self.n(b=1, *a, _, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 2), n(*OVER_STACK_ARGV)

    def self.o(b=1, *a, _, k: 1, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 2), o(*OVER_STACK_ARGV)
  end

  def test_call_iseq_large_array_splat_with_large_number_of_parameters
    args = OVER_STACK_ARGV.map{|i| "a#{i}"}.join(',')
    args1 = (OVER_STACK_LEN-1).times.map{|i| "a#{i}"}.join(',')

    singleton_class.class_eval("def a(#{args}); [#{args}] end")
    assert_equal OVER_STACK_ARGV, a(*OVER_STACK_ARGV)

    singleton_class.class_eval("def b(#{args}, b=0); [#{args}, b] end")
    assert_equal(OVER_STACK_ARGV + [0], b(*OVER_STACK_ARGV))

    singleton_class.class_eval("def c(#{args}, *b); [#{args}, b] end")
    assert_equal(OVER_STACK_ARGV + [[]], c(*OVER_STACK_ARGV))

    singleton_class.class_eval("def d(#{args1}, *b); [#{args1}, b] end")
    assert_equal(OVER_STACK_ARGV[0...-1] + [[OVER_STACK_ARGV.last]], d(*OVER_STACK_ARGV))
  end if OVER_STACK_LEN < 200

  def test_call_proc_large_array_splat_pass
    [
      proc{0} ,
      proc{|a=1|a},
      proc{|k: 1|0},
      proc{|**kw| 0},
      proc{|k: 1, **kw| 0},
      proc{|a=1, k: 1| a},
      proc{|a=1, **kw| a},
      proc{|a=1, k: 1, **kw| a},
    ].each do |l|
      assert_equal 0, l.call(*OVER_STACK_ARGV)
    end

    assert_equal OVER_STACK_LEN, proc{|*a| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|_, *a| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), proc{|_, *a, _| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|b=1, *a| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), proc{|b=1, *a, _| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|b=1, *a| a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, proc{|*a, k: 1| a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, proc{|*a, **kw| a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, proc{|*a, k: 1, **kw| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|b=1, *a, k: 1| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|b=1, *a, **kw| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), proc{|b=1, *a, k: 1, **kw| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), proc{|b=1, *a, _, k: 1| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), proc{|b=1, *a, _, **kw| a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), proc{|b=1, *a, _, k: 1, **kw| a.length}.(*OVER_STACK_ARGV)
  end

  def test_call_proc_large_array_splat_with_large_number_of_parameters
    args = OVER_STACK_ARGV.map{|i| "a#{i}"}.join(',')
    args1 = (OVER_STACK_LEN-1).times.map{|i| "a#{i}"}.join(',')

    l = instance_eval("proc{|#{args}| [#{args}]}")
    assert_equal OVER_STACK_ARGV, l.(*OVER_STACK_ARGV)

    l = instance_eval("proc{|#{args}, b| [#{args}, b]}")
    assert_equal(OVER_STACK_ARGV + [nil], l.(*OVER_STACK_ARGV))

    l = instance_eval("proc{|#{args1}| [#{args1}]}")
    assert_equal(OVER_STACK_ARGV[0...-1], l.(*OVER_STACK_ARGV))

    l = instance_eval("proc{|#{args}, *b| [#{args}, b]}")
    assert_equal(OVER_STACK_ARGV + [[]], l.(*OVER_STACK_ARGV))

    l = instance_eval("proc{|#{args1}, *b| [#{args1}, b]}")
    assert_equal(OVER_STACK_ARGV[0...-1] + [[OVER_STACK_ARGV.last]], l.(*OVER_STACK_ARGV))

    l = instance_eval("proc{|#{args}, b, *c| [#{args}, b, c]}")
    assert_equal(OVER_STACK_ARGV + [nil, []], l.(*OVER_STACK_ARGV))

    l = instance_eval("proc{|#{args}, b, *c, d| [#{args}, b, c, d]}")
    assert_equal(OVER_STACK_ARGV + [nil, [], nil], l.(*OVER_STACK_ARGV))
  end if OVER_STACK_LEN < 200

  def test_call_lambda_large_array_splat_fail
    [
      ->{} ,
      ->(a=1){},
      ->(k: 1){},
      ->(**kw){},
      ->(k: 1, **kw){},
      ->(a=1, k: 1){},
      ->(a=1, **kw){},
      ->(a=1, k: 1, **kw){},
    ].each do |l|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        l.call(*OVER_STACK_ARGV)
      end
    end
  end

  def test_call_lambda_large_array_splat_pass
    assert_equal OVER_STACK_LEN, ->(*a){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(_, *a){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), ->(_, *a, _){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(b=1, *a){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), ->(b=1, *a, _){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(b, *a){a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, ->(*a, k: 1){a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, ->(*a, **kw){a.length}.(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, ->(*a, k: 1, **kw){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(b=1, *a, k: 1){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(b=1, *a, **kw){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 1), ->(b=1, *a, k: 1, **kw){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), ->(b=1, *a, _, k: 1){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), ->(b=1, *a, _, **kw){a.length}.(*OVER_STACK_ARGV)
    assert_equal (OVER_STACK_LEN - 2), ->(b=1, *a, _, k: 1, **kw){a.length}.(*OVER_STACK_ARGV)
  end

  def test_call_yield_block_large_array_splat_pass
    def self.a
      yield(*OVER_STACK_ARGV)
    end

    [
      proc{0} ,
      proc{|a=1|a},
      proc{|k: 1|0},
      proc{|**kw| 0},
      proc{|k: 1, **kw| 0},
      proc{|a=1, k: 1| a},
      proc{|a=1, **kw| a},
      proc{|a=1, k: 1, **kw| a},
    ].each do |l|
      assert_equal 0, a(&l)
    end

    assert_equal OVER_STACK_LEN, a{|*a| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|_, *a| a.length}
    assert_equal (OVER_STACK_LEN - 2), a{|_, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|b=1, *a| a.length}
    assert_equal (OVER_STACK_LEN - 2), a{|b=1, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|b, *a| a.length}
    assert_equal OVER_STACK_LEN, a{|*a, k: 1| a.length}
    assert_equal OVER_STACK_LEN, a{|*a, **kw| a.length}
    assert_equal OVER_STACK_LEN, a{|*a, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|b=1, *a, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|b=1, *a, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), a{|b=1, *a, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), a{|b=1, *a, _, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 2), a{|b=1, *a, _, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), a{|b=1, *a, _, k: 1, **kw| a.length}
  end

  def test_call_yield_large_array_splat_with_large_number_of_parameters
    def self.a
      yield(*OVER_STACK_ARGV)
    end

    args = OVER_STACK_ARGV.map{|i| "a#{i}"}.join(',')
    args1 = (OVER_STACK_LEN-1).times.map{|i| "a#{i}"}.join(',')

    assert_equal OVER_STACK_ARGV, instance_eval("a{|#{args}| [#{args}]}", __FILE__, __LINE__)
    assert_equal(OVER_STACK_ARGV + [nil], instance_eval("a{|#{args}, b| [#{args}, b]}", __FILE__, __LINE__))
    assert_equal(OVER_STACK_ARGV[0...-1], instance_eval("a{|#{args1}| [#{args1}]}", __FILE__, __LINE__))
    assert_equal(OVER_STACK_ARGV + [[]], instance_eval("a{|#{args}, *b| [#{args}, b]}", __FILE__, __LINE__))
    assert_equal(OVER_STACK_ARGV[0...-1] + [[OVER_STACK_ARGV.last]], instance_eval("a{|#{args1}, *b| [#{args1}, b]}", __FILE__, __LINE__))
    assert_equal(OVER_STACK_ARGV + [nil, []], instance_eval("a{|#{args}, b, *c| [#{args}, b, c]}", __FILE__, __LINE__))
    assert_equal(OVER_STACK_ARGV + [nil, [], nil], instance_eval("a{|#{args}, b, *c, d| [#{args}, b, c, d]}", __FILE__, __LINE__))
  end if OVER_STACK_LEN < 200

  def test_call_yield_lambda_large_array_splat_fail
    def self.a
      yield(*OVER_STACK_ARGV)
    end
    [
      ->{} ,
      ->(a=1){},
      ->(k: 1){},
      ->(**kw){},
      ->(k: 1, **kw){},
      ->(a=1, k: 1){},
      ->(a=1, **kw){},
      ->(a=1, k: 1, **kw){},
    ].each do |l|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        a(&l)
      end
    end
  end

  def test_call_yield_lambda_large_array_splat_pass
    def self.a
      yield(*OVER_STACK_ARGV)
    end

    assert_equal OVER_STACK_LEN, a(&->(*a){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(_, *a){a.length})
    assert_equal (OVER_STACK_LEN - 2), a(&->(_, *a, _){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(b=1, *a){a.length})
    assert_equal (OVER_STACK_LEN - 2), a(&->(b=1, *a, _){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(b, *a){a.length})
    assert_equal OVER_STACK_LEN, a(&->(*a, k: 1){a.length})
    assert_equal OVER_STACK_LEN, a(&->(*a, **kw){a.length})
    assert_equal OVER_STACK_LEN, a(&->(*a, k: 1, **kw){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(b=1, *a, k: 1){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(b=1, *a, **kw){a.length})
    assert_equal (OVER_STACK_LEN - 1), a(&->(b=1, *a, k: 1, **kw){a.length})
    assert_equal (OVER_STACK_LEN - 2), a(&->(b=1, *a, _, k: 1){a.length})
    assert_equal (OVER_STACK_LEN - 2), a(&->(b=1, *a, _, **kw){a.length})
    assert_equal (OVER_STACK_LEN - 2), a(&->(b=1, *a, _, k: 1, **kw){a.length})
  end

  def test_call_send_iseq_large_array_splat_fail
    def self.a; end
    def self.b(a=1); end
    def self.c(k: 1); end
    def self.d(**kw); end
    def self.e(k: 1, **kw); end
    def self.f(a=1, k: 1); end
    def self.g(a=1, **kw); end
    def self.h(a=1, k: 1, **kw); end

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        send(meth, *OVER_STACK_ARGV)
      end
    end
  end

  def test_call_send_iseq_large_array_splat_pass
    def self.a(*a); a.length end
    assert_equal OVER_STACK_LEN, send(:a, *OVER_STACK_ARGV)

    def self.b(_, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:b, *OVER_STACK_ARGV)

    def self.c(_, *a, _); a.length end
    assert_equal (OVER_STACK_LEN - 2), send(:c, *OVER_STACK_ARGV)

    def self.d(b=1, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:d, *OVER_STACK_ARGV)

    def self.e(b=1, *a, _); a.length end
    assert_equal (OVER_STACK_LEN - 2), send(:e, *OVER_STACK_ARGV)

    def self.f(b, *a); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:f, *OVER_STACK_ARGV)

    def self.g(*a, k: 1); a.length end
    assert_equal OVER_STACK_LEN, send(:g, *OVER_STACK_ARGV)

    def self.h(*a, **kw); a.length end
    assert_equal OVER_STACK_LEN, send(:h, *OVER_STACK_ARGV)

    def self.i(*a, k: 1, **kw); a.length end
    assert_equal OVER_STACK_LEN, send(:i, *OVER_STACK_ARGV)

    def self.j(b=1, *a, k: 1); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:j, *OVER_STACK_ARGV)

    def self.k(b=1, *a, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:k, *OVER_STACK_ARGV)

    def self.l(b=1, *a, k: 1, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 1), send(:l, *OVER_STACK_ARGV)

    def self.m(b=1, *a, _, k: 1); a.length end
    assert_equal (OVER_STACK_LEN - 2), send(:m, *OVER_STACK_ARGV)

    def self.n(b=1, *a, _, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 2), send(:n, *OVER_STACK_ARGV)

    def self.o(b=1, *a, _, k: 1, **kw); a.length end
    assert_equal (OVER_STACK_LEN - 2), send(:o, *OVER_STACK_ARGV)
  end

  def test_call_send_iseq_large_array_splat_with_large_number_of_parameters
    args = OVER_STACK_ARGV.map{|i| "a#{i}"}.join(',')
    args1 = (OVER_STACK_LEN-1).times.map{|i| "a#{i}"}.join(',')

    singleton_class.class_eval("def a(#{args}); [#{args}] end")
    assert_equal OVER_STACK_ARGV, send(:a, *OVER_STACK_ARGV)

    singleton_class.class_eval("def b(#{args}, b=0); [#{args}, b] end")
    assert_equal(OVER_STACK_ARGV + [0], send(:b, *OVER_STACK_ARGV))

    singleton_class.class_eval("def c(#{args}, *b); [#{args}, b] end")
    assert_equal(OVER_STACK_ARGV + [[]], send(:c, *OVER_STACK_ARGV))

    singleton_class.class_eval("def d(#{args1}, *b); [#{args1}, b] end")
    assert_equal(OVER_STACK_ARGV[0...-1] + [[OVER_STACK_ARGV.last]], send(:d, *OVER_STACK_ARGV))
  end if OVER_STACK_LEN < 200

  def test_call_send_cfunc_large_array_splat_fail
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      send(:object_id, *OVER_STACK_ARGV)
    end
  end

  def test_call_send_cfunc_large_array_splat_pass
    assert_equal OVER_STACK_LEN, [].send(:push, *OVER_STACK_ARGV).length
  end

  def test_call_attr_reader_large_array_splat_fail
    singleton_class.send(:attr_reader, :a)
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      a(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      send(:a, *OVER_STACK_ARGV)
    end
  end

  def test_call_attr_writer_large_array_splat_fail
    singleton_class.send(:attr_writer, :a)
    singleton_class.send(:alias_method, :a, :a=)

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 1)") do
      a(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 1)") do
      send(:a, *OVER_STACK_ARGV)
    end
  end

  def test_call_struct_aref_large_array_splat_fail
    s = Struct.new(:a).new
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      s.a(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      s.send(:a, *OVER_STACK_ARGV)
    end
  end

  def test_call_struct_aset_large_array_splat_fail
    s = Struct.new(:a) do
      alias b a=
    end.new
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 1)") do
      s.b(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 1)") do
      s.send(:b, *OVER_STACK_ARGV)
    end
  end

  def test_call_alias_large_array_splat
    c = Class.new do
      def a; end
      def c(*a); a.length end
      attr_accessor :e
    end
    sc = Class.new(c) do
      alias b a
      alias d c
      alias f e
      alias g e=
    end

    obj = sc.new
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      obj.b(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      obj.f(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 1)") do
      obj.g(*OVER_STACK_ARGV)
    end

    assert_equal OVER_STACK_LEN, obj.d(*OVER_STACK_ARGV)
  end

  def test_call_zsuper_large_array_splat
    c = Class.new do
      private
      def a; end
      def c(*a); a.length end
      attr_reader :e
    end
    sc = Class.new(c) do
      public :a
      public :c
      public :e
    end

    obj = sc.new
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      obj.a(*OVER_STACK_ARGV)
    end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      obj.e(*OVER_STACK_ARGV)
    end

    assert_equal OVER_STACK_LEN, obj.c(*OVER_STACK_ARGV)
  end

  class RefinedModuleLargeArrayTest
    c = self
    using(Module.new do
      refine c do
        def a; end
        def c(*a) a.length end
        attr_reader :e
      end
    end)

    def b
      a(*OVER_STACK_ARGV)
    end

    def d
      c(*OVER_STACK_ARGV)
    end

    def f
      e(*OVER_STACK_ARGV)
    end
  end

  def test_call_refined_large_array_splat_fail
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      RefinedModuleLargeArrayTest.new.b
    end

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN}, expected 0)") do
      RefinedModuleLargeArrayTest.new.f
    end
  end

  def test_call_refined_large_array_splat_pass
    assert_equal OVER_STACK_LEN, RefinedModuleLargeArrayTest.new.d
  end

  def test_call_method_missing_iseq_large_array_splat_fail
    def self.method_missing(_) end
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      nonexistent_method(*OVER_STACK_ARGV)
    end

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      send(:nonexistent_method, *OVER_STACK_ARGV)
    end

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      send("nonexistent_method123", *OVER_STACK_ARGV)
    end
  end

  def test_call_method_missing_iseq_large_array_splat_pass
    def self.method_missing(m, *a)
      a.length
    end
    assert_equal OVER_STACK_LEN, nonexistent_method(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, send(:nonexistent_method, *OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, send("nonexistent_method123", *OVER_STACK_ARGV)
  end

  def test_call_bmethod_large_array_splat_fail
    define_singleton_method(:a){}
    define_singleton_method(:b){|a=1|}
    define_singleton_method(:c){|k: 1|}
    define_singleton_method(:d){|**kw|}
    define_singleton_method(:e){|k: 1, **kw|}
    define_singleton_method(:f){|a=1, k: 1|}
    define_singleton_method(:g){|a=1, **kw|}
    define_singleton_method(:h){|a=1, k: 1, **kw|}

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        instance_eval("#{meth}(*OVER_STACK_ARGV)", __FILE__, __LINE__)
      end
    end
  end

  def test_call_bmethod_large_array_splat_pass
    define_singleton_method(:a){|*a| a.length}
    assert_equal OVER_STACK_LEN, a(*OVER_STACK_ARGV)

    define_singleton_method(:b){|_, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), b(*OVER_STACK_ARGV)

    define_singleton_method(:c){|_, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), c(*OVER_STACK_ARGV)

    define_singleton_method(:d){|b=1, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), d(*OVER_STACK_ARGV)

    define_singleton_method(:e){|b=1, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), e(*OVER_STACK_ARGV)

    define_singleton_method(:f){|b, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), f(*OVER_STACK_ARGV)

    define_singleton_method(:g){|*a, k: 1| a.length}
    assert_equal OVER_STACK_LEN, g(*OVER_STACK_ARGV)

    define_singleton_method(:h){|*a, **kw| a.length}
    assert_equal OVER_STACK_LEN, h(*OVER_STACK_ARGV)

    define_singleton_method(:i){|*a, k: 1, **kw| a.length}
    assert_equal OVER_STACK_LEN, i(*OVER_STACK_ARGV)

    define_singleton_method(:j){|b=1, *a, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 1), j(*OVER_STACK_ARGV)

    define_singleton_method(:k){|b=1, *a, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), k(*OVER_STACK_ARGV)

    define_singleton_method(:l){|b=1, *a, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), l(*OVER_STACK_ARGV)

    define_singleton_method(:m){|b=1, *a, _, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 2), m(*OVER_STACK_ARGV)

    define_singleton_method(:n){|b=1, *a, _, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), n(*OVER_STACK_ARGV)

    define_singleton_method(:o){|b=1, *a, _, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), o(*OVER_STACK_ARGV)
  end

  def test_call_method_missing_bmethod_large_array_splat_fail
    define_singleton_method(:method_missing){|_|}
    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      nonexistent_method(*OVER_STACK_ARGV)
    end

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      send(:nonexistent_method, *OVER_STACK_ARGV)
    end

    assert_raise_with_message(ArgumentError, "wrong number of arguments (given #{OVER_STACK_LEN+1}, expected 1)") do
      send("nonexistent_method123", *OVER_STACK_ARGV)
    end
  end

  def test_call_method_missing_bmethod_large_array_splat_pass
    define_singleton_method(:method_missing){|_, *a| a.length}
    assert_equal OVER_STACK_LEN, nonexistent_method(*OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, send(:nonexistent_method, *OVER_STACK_ARGV)
    assert_equal OVER_STACK_LEN, send("nonexistent_method123", *OVER_STACK_ARGV)
  end

  def test_call_symproc_large_array_splat_fail
    define_singleton_method(:a){}
    define_singleton_method(:b){|a=1|}
    define_singleton_method(:c){|k: 1|}
    define_singleton_method(:d){|**kw|}
    define_singleton_method(:e){|k: 1, **kw|}
    define_singleton_method(:f){|a=1, k: 1|}
    define_singleton_method(:g){|a=1, **kw|}
    define_singleton_method(:h){|a=1, k: 1, **kw|}

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        instance_eval(":#{meth}.to_proc.(self, *OVER_STACK_ARGV)", __FILE__, __LINE__)
      end
    end
  end

  def test_call_symproc_large_array_splat_pass
    define_singleton_method(:a){|*a| a.length}
    assert_equal OVER_STACK_LEN, :a.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:b){|_, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), :b.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:c){|_, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), :c.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:d){|b=1, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), :d.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:e){|b=1, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), :e.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:f){|b, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), :f.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:g){|*a, k: 1| a.length}
    assert_equal OVER_STACK_LEN, :g.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:h){|*a, **kw| a.length}
    assert_equal OVER_STACK_LEN, :h.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:i){|*a, k: 1, **kw| a.length}
    assert_equal OVER_STACK_LEN, :i.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:j){|b=1, *a, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 1), :j.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:k){|b=1, *a, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), :k.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:l){|b=1, *a, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), :l.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:m){|b=1, *a, _, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 2), :m.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:n){|b=1, *a, _, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), :n.to_proc.(self, *OVER_STACK_ARGV)

    define_singleton_method(:o){|b=1, *a, _, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), :o.to_proc.(self, *OVER_STACK_ARGV)
  end

  def test_call_rb_call_iseq_large_array_splat_fail
    extend Bug::Iter::Yield
    l = ->(*a){}

    def self.a; end
    def self.b(a=1) end
    def self.c(k: 1) end
    def self.d(**kw) end
    def self.e(k: 1, **kw) end
    def self.f(a=1, k: 1) end
    def self.g(a=1, **kw) end
    def self.h(a=1, k: 1, **kw) end

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        yield_block(meth, *OVER_STACK_ARGV, &l)
      end
    end
  end

  def test_call_rb_call_iseq_large_array_splat_pass
    extend Bug::Iter::Yield
    l = ->(*a){a.length}

    def self.a(*a) a.length end
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    def self.b(_, *a) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:b, *OVER_STACK_ARGV, &l)

    def self.c(_, *a, _) a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:c, *OVER_STACK_ARGV, &l)

    def self.d(b=1, *a) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:d, *OVER_STACK_ARGV, &l)

    def self.e(b=1, *a, _) a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:e, *OVER_STACK_ARGV, &l)

    def self.f(b, *a) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:f, *OVER_STACK_ARGV, &l)

    def self.g(*a, k: 1) a.length end
    assert_equal OVER_STACK_LEN, yield_block(:g, *OVER_STACK_ARGV, &l)

    def self.h(*a, **kw) a.length end
    assert_equal OVER_STACK_LEN, yield_block(:h, *OVER_STACK_ARGV, &l)

    def self.i(*a, k: 1, **kw) a.length end
    assert_equal OVER_STACK_LEN, yield_block(:h, *OVER_STACK_ARGV, &l)

    def self.j(b=1, *a, k: 1) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:j, *OVER_STACK_ARGV, &l)

    def self.k(b=1, *a, **kw) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:k, *OVER_STACK_ARGV, &l)

    def self.l(b=1, *a, k: 1, **kw) a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:l, *OVER_STACK_ARGV, &l)

    def self.m(b=1, *a, _, k: 1) a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:m, *OVER_STACK_ARGV, &l)

    def self.n(b=1, *a, _, **kw) a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:n, *OVER_STACK_ARGV, &l)

    def self.o(b=1, *a, _, k: 1, **kw) a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:o, *OVER_STACK_ARGV, &l)
  end

  def test_call_rb_call_bmethod_large_array_splat_fail
    extend Bug::Iter::Yield
    l = ->(*a){}

    define_singleton_method(:a){||}
    define_singleton_method(:b){|a=1|}
    define_singleton_method(:c){|k: 1|}
    define_singleton_method(:d){|**kw|}
    define_singleton_method(:e){|k: 1, **kw|}
    define_singleton_method(:f){|a=1, k: 1|}
    define_singleton_method(:g){|a=1, **kw|}
    define_singleton_method(:h){|a=1, k: 1, **kw|}

    (:a..:h).each do |meth|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        yield_block(meth, *OVER_STACK_ARGV, &l)
      end
    end
  end

  def test_call_rb_call_bmethod_large_array_splat_pass
    extend Bug::Iter::Yield
    l = ->(*a){a.length}

    define_singleton_method(:a){|*a| a.length}
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    define_singleton_method(:b){|_, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:b, *OVER_STACK_ARGV, &l)

    define_singleton_method(:c){|_, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), yield_block(:c, *OVER_STACK_ARGV, &l)

    define_singleton_method(:d){|b=1, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:d, *OVER_STACK_ARGV, &l)

    define_singleton_method(:e){|b=1, *a, _| a.length}
    assert_equal (OVER_STACK_LEN - 2), yield_block(:e, *OVER_STACK_ARGV, &l)

    define_singleton_method(:f){|b, *a| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:f, *OVER_STACK_ARGV, &l)

    define_singleton_method(:g){|*a, k: 1| a.length}
    assert_equal OVER_STACK_LEN, yield_block(:g, *OVER_STACK_ARGV, &l)

    define_singleton_method(:h){|*a, **kw| a.length}
    assert_equal OVER_STACK_LEN, yield_block(:h, *OVER_STACK_ARGV, &l)

    define_singleton_method(:i){|*a, k: 1, **kw| a.length}
    assert_equal OVER_STACK_LEN, yield_block(:h, *OVER_STACK_ARGV, &l)

    define_singleton_method(:j){|b=1, *a, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:j, *OVER_STACK_ARGV, &l)

    define_singleton_method(:k){|b=1, *a, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:k, *OVER_STACK_ARGV, &l)

    define_singleton_method(:l){|b=1, *a, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 1), yield_block(:l, *OVER_STACK_ARGV, &l)

    define_singleton_method(:m){|b=1, *a, _, k: 1| a.length}
    assert_equal (OVER_STACK_LEN - 2), yield_block(:m, *OVER_STACK_ARGV, &l)

    define_singleton_method(:n){|b=1, *a, _, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), yield_block(:n, *OVER_STACK_ARGV, &l)

    define_singleton_method(:o){|b=1, *a, _, k: 1, **kw| a.length}
    assert_equal (OVER_STACK_LEN - 2), yield_block(:o, *OVER_STACK_ARGV, &l)
  end

  def test_call_ifunc_iseq_large_array_splat_fail
    extend Bug::Iter::Yield
    def self.a(*a)
      yield(*a)
    end
    [
      ->(){},
      ->(a=1){},
      ->(k: 1){},
      ->(**kw){},
      ->(k: 1, **kw){},
      ->(a=1, k: 1){},
      ->(a=1, **kw){},
      ->(a=1, k: 1, **kw){},
    ].each do |l|
      assert_raise_with_message(ArgumentError, /wrong number of arguments \(given #{OVER_STACK_LEN}, expected 0(\.\.[12])?\)/) do
        yield_block(:a, *OVER_STACK_ARGV, &l)
      end
    end
  end

  def test_call_ifunc_iseq_large_array_splat_pass
    extend Bug::Iter::Yield
    def self.a(*a)
      yield(*a)
    end

    l = ->(*a) do a.length end
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(_, *a) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(_, *a, _) do a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, _) do a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b, *a) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(*a, k: 1) do a.length end
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(*a, **kw) do a.length end
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(*a, k: 1, **kw) do a.length end
    assert_equal OVER_STACK_LEN, yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, k: 1) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, **kw) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, k: 1, **kw) do a.length end
    assert_equal (OVER_STACK_LEN - 1), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, _, k: 1) do a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, _, **kw) do a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:a, *OVER_STACK_ARGV, &l)

    l = ->(b=1, *a, _, k: 1, **kw) do a.length end
    assert_equal (OVER_STACK_LEN - 2), yield_block(:a, *OVER_STACK_ARGV, &l)
  end
end
