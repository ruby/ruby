# frozen_string_literal: true
require 'test/unit'

experimental, Warning[:experimental] = Warning[:experimental], false # suppress "warning: Pattern matching is experimental, and the behavior may change in future versions of Ruby!"
eval "\n#{<<~'END_of_GUARD'}", binding, __FILE__, __LINE__
class TestPatternMatching < Test::Unit::TestCase
  class C
    class << self
      attr_accessor :keys
    end

    def initialize(obj)
      @obj = obj
    end

    def deconstruct
      @obj
    end

    def deconstruct_keys(keys)
      C.keys = keys
      @obj
    end
  end

  def test_basic
    assert_block do
      case 0
      in 0
        true
      else
        false
      end
    end

    assert_block do
      case 0
      in 1
        false
      else
        true
      end
    end

    assert_raise(NoMatchingPatternError) do
      case 0
      in 1
        false
      end
    end

    begin
      o = [0]
      case o
      in 1
        false
      end
    rescue => e
      assert_match o.inspect, e.message
    end

    assert_block do
      begin
        true
      ensure
        case 0
        in 0
          false
        end
      end
    end

    assert_block do
      begin
        true
      ensure
        case 0
        in 1
        else
          false
        end
      end
    end

    assert_raise(NoMatchingPatternError) do
      begin
      ensure
        case 0
        in 1
        end
      end
    end

    assert_block do
      # suppress "warning: Pattern matching is experimental, and the behavior may change in future versions of Ruby!"
      experimental, Warning[:experimental] = Warning[:experimental], false
      eval(%q{
        case true
        in a
          a
        end
      })
    ensure
      Warning[:experimental] = experimental
    end

    assert_block do
      tap do |a|
        tap do
          case true
          in a
            a
          end
        end
      end
    end

    assert_raise(NoMatchingPatternError) do
      o = BasicObject.new
      def o.match
        case 0
        in 1
        end
      end
      o.match
    end
  end

  def test_modifier
    assert_block do
      case 0
      in a if a == 0
        true
      end
    end

    assert_block do
      case 0
      in a if a != 0
      else
        true
      end
    end

    assert_block do
      case 0
      in a unless a != 0
        true
      end
    end

    assert_block do
      case 0
      in a unless a == 0
      else
        true
      end
    end
  end

  def test_as_pattern
    assert_block do
      case 0
      in 0 => a
        a == 0
      end
    end
  end

  def test_alternative_pattern
    assert_block do
      [0, 1].all? do |i|
        case i
        in 0 | 1
          true
        end
      end
    end

    assert_block do
      case 0
      in _ | _a
        true
      end
    end

    assert_syntax_error(%q{
      case 0
      in a | 0
      end
    }, /illegal variable in alternative pattern/)
  end

  def test_var_pattern
    # NODE_DASGN_CURR
    assert_block do
      case 0
      in a
        a == 0
      end
    end

    # NODE_DASGN
    b = 0
    assert_block do
      case 1
      in b
        b == 1
      end
    end

    # NODE_LASGN
    case 0
    in c
      assert_equal(0, c)
    else
      flunk
    end

    assert_syntax_error(%q{
      case 0
      in ^a
      end
    }, /no such local variable/)

    assert_syntax_error(%q{
      case 0
      in a, a
      end
    }, /duplicated variable name/)

    assert_block do
      case [0, 1, 2, 3]
      in _, _, _a, _a
        true
      end
    end

    assert_syntax_error(%q{
      case 0
      in a, {a:}
      end
    }, /duplicated variable name/)

    assert_syntax_error(%q{
      case 0
      in a, {"a":}
      end
    }, /duplicated variable name/)

    assert_block do
      case [0, "1"]
      in a, "#{case 1; in a; a; end}"
        true
      end
    end

    assert_syntax_error(%q{
      case [0, "1"]
      in a, "#{case 1; in a; a; end}", a
      end
    }, /duplicated variable name/)

    assert_block do
      case 0
      in a
        assert_equal(0, a)
        true
      in a
        flunk
      end
    end

    assert_syntax_error(%q{
      0 in [a, a]
    }, /duplicated variable name/)
  end

  def test_literal_value_pattern
    assert_block do
      case [nil, self, true, false]
      in [nil, self, true, false]
        true
      end
    end

    assert_block do
      case [0d170, 0D170, 0xaa, 0xAa, 0xAA, 0Xaa, 0XAa, 0XaA, 0252, 0o252, 0O252]
      in [0d170, 0D170, 0xaa, 0xAa, 0xAA, 0Xaa, 0XAa, 0XaA, 0252, 0o252, 0O252]
        true
      end

      case [0b10101010, 0B10101010, 12r, 12.3r, 1i, 12.3ri]
      in [0b10101010, 0B10101010, 12r, 12.3r, 1i, 12.3ri]
        true
      end
    end

    assert_block do
      x = 'x'
      case ['a', 'a', x]
      in ['a', "a", "#{x}"]
        true
      end
    end

    assert_block do
      case ["a\n"]
      in [<<END]
a
END
        true
      end
    end

    assert_block do
      case [:a, :"a"]
      in [:a, :"a"]
        true
      end
    end

    assert_block do
      case [0, 1, 2, 3, 4, 5]
      in [0..1, 0...2, 0.., 0..., (...5), (..5)]
        true
      end
    end

    assert_syntax_error(%q{
      case 0
      in a..b
      end
    }, /unexpected/)

    assert_block do
      case 'abc'
      in /a/
        true
      end
    end

    assert_block do
      case 0
      in ->(i) { i == 0 }
        true
      end
    end

    assert_block do
      case [%(a), %q(a), %Q(a), %w(a), %W(a), %i(a), %I(a), %s(a), %x(echo a), %(), %q(), %Q(), %w(), %W(), %i(), %I(), %s(), 'a']
      in [%(a), %q(a), %Q(a), %w(a), %W(a), %i(a), %I(a), %s(a), %x(echo a), %(), %q(), %Q(), %w(), %W(), %i(), %I(), %s(), %r(a)]
        true
      end
    end

    assert_block do
      case [__FILE__, __LINE__ + 1, __ENCODING__]
      in [__FILE__, __LINE__, __ENCODING__]
        true
      end
    end
  end

  def test_constant_value_pattern
    assert_block do
      case 0
      in Integer
        true
      end
    end

    assert_block do
      case 0
      in Object::Integer
        true
      end
    end

    assert_block do
      case 0
      in ::Object::Integer
        true
      end
    end
  end

  def test_pin_operator_value_pattern
    assert_block do
      a = /a/
      case 'abc'
      in ^a
        true
      end
    end

    assert_block do
      case [0, 0]
      in a, ^a
        a == 0
      end
    end
  end

  def test_array_pattern
    assert_block do
      [[0], C.new([0])].all? do |i|
        case i
        in 0,;
          true
        end
      end
    end

    assert_block do
      [[0, 1], C.new([0, 1])].all? do |i|
        case i
        in 0,;
          true
        end
      end
    end

    assert_block do
      [[], C.new([])].all? do |i|
        case i
        in 0,;
        else
          true
        end
      end
    end

    assert_block do
      [[0, 1], C.new([0, 1])].all? do |i|
        case i
        in 0, 1
          true
        end
      end
    end

    assert_block do
      [[0], C.new([0])].all? do |i|
        case i
        in 0, 1
        else
          true
        end
      end
    end

    assert_block do
      [[], C.new([])].all? do |i|
        case i
        in *a
          a == []
        end
      end
    end

    assert_block do
      [[0], C.new([0])].all? do |i|
        case i
        in *a
          a == [0]
        end
      end
    end

    assert_block do
      [[0], C.new([0])].all? do |i|
        case i
        in *a, 0, 1
          raise a # suppress "unused variable: a" warning
        else
          true
        end
      end
    end

    assert_block do
      [[0, 1], C.new([0, 1])].all? do |i|
        case i
        in *a, 0, 1
          a == []
        end
      end
    end

    assert_block do
      [[0, 1, 2], C.new([0, 1, 2])].all? do |i|
        case i
        in *a, 1, 2
          a == [0]
        end
      end
    end

    assert_block do
      [[], C.new([])].all? do |i|
        case i
        in *;
          true
        end
      end
    end

    assert_block do
      [[0], C.new([0])].all? do |i|
        case i
        in *, 0, 1
        else
          true
        end
      end
    end

    assert_block do
      [[0, 1], C.new([0, 1])].all? do |i|
        case i
        in *, 0, 1
          true
        end
      end
    end

    assert_block do
      [[0, 1, 2], C.new([0, 1, 2])].all? do |i|
        case i
        in *, 1, 2
          true
        end
      end
    end

    assert_block do
      case C.new([0])
      in C(0)
        true
      end
    end

    assert_block do
      case C.new([0])
      in Array(0)
      else
        true
      end
    end

    assert_block do
      case C.new([])
      in C()
        true
      end
    end

    assert_block do
      case C.new([])
      in Array()
      else
        true
      end
    end

    assert_block do
      case C.new([0])
      in C[0]
        true
      end
    end

    assert_block do
      case C.new([0])
      in Array[0]
      else
        true
      end
    end

    assert_block do
      case C.new([])
      in C[]
        true
      end
    end

    assert_block do
      case C.new([])
      in Array[]
      else
        true
      end
    end

    assert_block do
      case []
      in []
        true
      end
    end

    assert_block do
      case C.new([])
      in []
        true
      end
    end

    assert_block do
      case [0]
      in [0]
        true
      end
    end

    assert_block do
      case C.new([0])
      in [0]
        true
      end
    end

    assert_block do
      case [0]
      in [0,]
        true
      end
    end

    assert_block do
      case [0, 1]
      in [0,]
        true
      end
    end

    assert_block do
      case []
      in [0, *a]
        raise a # suppress "unused variable: a" warning
      else
        true
      end
    end

    assert_block do
      case [0]
      in [0, *a]
        a == []
      end
    end

    assert_block do
      case [0]
      in [0, *a, 1]
        raise a # suppress "unused variable: a" warning
      else
        true
      end
    end

    assert_block do
      case [0, 1]
      in [0, *a, 1]
        a == []
      end
    end

    assert_block do
      case [0, 1, 2]
      in [0, *a, 2]
        a == [1]
      end
    end

    assert_block do
      case []
      in [0, *]
      else
        true
      end
    end

    assert_block do
      case [0]
      in [0, *]
        true
      end
    end

    assert_block do
      case [0, 1]
      in [0, *]
        true
      end
    end

    assert_block do
      case []
      in [0, *a]
        raise a # suppress "unused variable: a" warning
      else
        true
      end
    end

    assert_block do
      case [0]
      in [0, *a]
        a == []
      end
    end

    assert_block do
      case [0, 1]
      in [0, *a]
        a == [1]
      end
    end

    assert_block do
      case [0]
      in [0, *, 1]
      else
        true
      end
    end

    assert_block do
      case [0, 1]
      in [0, *, 1]
        true
      end
    end
  end

  def test_find_pattern
    [0, 1, 2] in [*, 1 => a, *]
    assert_equal(1, a)

    [0, 1, 2] in [*a, 1 => b, *c]
    assert_equal([0], a)
    assert_equal(1, b)
    assert_equal([2], c)

    assert_block do
      case [0, 1, 2]
      in [*, 9, *]
        false
      else
        true
      end
    end

    assert_block do
      case [0, 1, 2]
      in [*, Integer, String, *]
        false
      else
        true
      end
    end

    [0, 1, 2] in [*a, 1 => b, 2 => c, *d]
    assert_equal([0], a)
    assert_equal(1, b)
    assert_equal(2, c)
    assert_equal([], d)

    case [0, 1, 2]
    in *, 1 => a, *;
        assert_equal(1, a)
    end

    assert_block do
      case [0, 1, 2]
      in String(*, 1, *)
        false
      in Array(*, 1, *)
        true
      end
    end

    assert_block do
      case [0, 1, 2]
      in String[*, 1, *]
        false
      in Array[*, 1, *]
        true
      end
    end
  end

  def test_hash_pattern
    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in a: 0
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in a: 0
          true
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in a: 0
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in a: 0, b: 1
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in a: 0, b: 1
          true
        end
      end
    end

    assert_block do
      [{a: 0, b: 1, c: 2}, C.new({a: 0, b: 1, c: 2})].all? do |i|
        case i
        in a: 0, b: 1
          true
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in a:
          raise a # suppress "unused variable: a" warning
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in a:
          a == 0
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in a:
          a == 0
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in "a": 0
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in "a":;
          a == 0
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in **a
          a == {}
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in **a
          a == {a: 0}
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in **;
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in **;
          true
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in a:, **b
          raise a # suppress "unused variable: a" warning
          raise b # suppress "unused variable: b" warning
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in a:, **b
          a == 0 && b == {}
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in a:, **b
          a == 0 && b == {b: 1}
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in **nil
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in **nil
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in a:, **nil
          assert_equal(0, a)
          true
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in a:, **nil
          assert_equal(0, a)
        else
          true
        end
      end
    end

    assert_block do
      case C.new({a: 0})
      in C(a: 0)
        true
      end
    end

    assert_block do
      case {a: 0}
      in C(a: 0)
      else
        true
      end
    end

    assert_block do
      case C.new({a: 0})
      in C[a: 0]
        true
      end
    end

    assert_block do
      case {a: 0}
      in C[a: 0]
      else
        true
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in {a: 0}
        else
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in {a: 0}
          true
        end
      end
    end

    assert_block do
      [{a: 0, b: 1}, C.new({a: 0, b: 1})].all? do |i|
        case i
        in {a: 0}
          true
        end
      end
    end

    assert_block do
      [{}, C.new({})].all? do |i|
        case i
        in {}
          true
        end
      end
    end

    assert_block do
      [{a: 0}, C.new({a: 0})].all? do |i|
        case i
        in {}
        else
          true
        end
      end
    end

    assert_block do
      m = /(?<a>.)/.match('x')

      # Temporary patch in ruby to make tests pass until the code gets re-written in C
      def m.deconstruct_keys(*keys)
        h0 = named_captures.transform_keys(&:to_sym)
        if keys
          keys = keys.flatten.compact
          raise TypeError unless keys.all? { |k| k.is_a?(Symbol) }
          h0 = h0.slice(*keys) unless keys.empty?
        end
        h0.inject({}) { |h, (k, v)| h[k] = v if v; h }
      end
      # Temporary patch in ruby to make tests pass until the code gets re-written in C

      [m].all? do |i|
        case i
        in {a: 'x'}
          true
        end
      end
    end

    assert_syntax_error(%q{
      case _
      in a:, a:
      end
    }, /duplicated key name/)

    assert_syntax_error(%q{
      case _
      in a?:
      end
    }, /key must be valid as local variables/)

    assert_block do
      case {a?: true}
      in a?: true
        true
      end
    end

    assert_block do
      case {a: 0, b: 1}
      in {a: 1,}
        false
      in {a:,}
        _a = a
        true
      end
    end

    assert_block do
      case {a: 0}
      in {a: 1
      }
        false
      in {a:
            2}
        false
      in a: {b:}, c:
        _b = b
        p c
      in {a:
      }
        _a = a
        true
      end
    end

    assert_syntax_error(%q{
      case _
      in "a-b":
      end
    }, /key must be valid as local variables/)

    assert_block do
      case {"a-b": true}
      in "a-b": true
        true
      end
    end

    assert_syntax_error(%q{
      case _
      in "#{a}": a
      end
    }, /symbol literal with interpolation is not allowed/)

    assert_syntax_error(%q{
      case _
      in "#{a}":
      end
    }, /symbol literal with interpolation is not allowed/)
  end

  def test_paren
    assert_block do
      case 0
      in (0)
        true
      end
    end
  end

  def test_invalid_syntax
    assert_syntax_error(%q{
      case 0
      in a, b:
      end
    }, /unexpected/)

    assert_syntax_error(%q{
      case 0
      in [a:]
      end
    }, /unexpected/)

    assert_syntax_error(%q{
      case 0
      in {a}
      end
    }, /unexpected/)

    assert_syntax_error(%q{
      case 0
      in {0 => a}
      end
    }, /unexpected/)
  end

  ################################################################

  class CTypeError
    def deconstruct
      nil
    end

    def deconstruct_keys(keys)
      nil
    end
  end

  def test_deconstruct
    assert_raise(TypeError) do
      case CTypeError.new
      in []
      end
    end
  end

  def test_deconstruct_keys
    assert_raise(TypeError) do
      case CTypeError.new
      in {}
      end
    end

    assert_block do
      case {}
      in {}
        C.keys == nil
      end
    end

    assert_block do
      case C.new({a: 0, b: 0, c: 0})
      in {a: 0, b:}
        assert_equal(0, b)
        C.keys == [:a, :b]
      end
    end

    assert_block do
      case C.new({a: 0, b: 0, c: 0})
      in {a: 0, b:, **}
        assert_equal(0, b)
        C.keys == [:a, :b]
      end
    end

    assert_block do
      case C.new({a: 0, b: 0, c: 0})
      in {a: 0, b:, **r}
        assert_equal(0, b)
        assert_equal({c: 0}, r)
        C.keys == nil
      end
    end

    assert_block do
      case C.new({a: 0, b: 0, c: 0})
      in {**}
        C.keys == []
      end
    end

    assert_block do
      case C.new({a: 0, b: 0, c: 0})
      in {**r}
        assert_equal({a: 0, b: 0, c: 0}, r)
        C.keys == nil
      end
    end
  end

  ################################################################

  class CDeconstructCache
    def initialize(v)
      @v = v
    end

    def deconstruct
      @v.shift
    end
  end

  def test_deconstruct_cache
    assert_block do
      case CDeconstructCache.new([[0]])
      in [1]
      in [0]
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[0, 1]])
      in [1,]
      in [0,]
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[[0]]])
      in [[1]]
      in [[*a]]
        a == [0]
      end
    end

    assert_block do
      case CDeconstructCache.new([[0]])
      in [x] if x > 0
      in [0]
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[0]])
      in []
      in [1] | [0]
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[0]])
      in [1] => _
      in [0] => _
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[0]])
      in C[0]
      in CDeconstructCache[0]
        true
      end
    end

    assert_block do
      case [CDeconstructCache.new([[0], [1]])]
      in [[1]]
        false
      in [[1]]
        true
      end
    end

    assert_block do
      case CDeconstructCache.new([[0, :a, 1]])
      in [*, String => x, *]
        false
      in [*, Symbol => x, *]
        x == :a
      end
    end
  end

  ################################################################

  class TestPatternMatchingRefinements < Test::Unit::TestCase
    class C1
      def deconstruct
        [:C1]
      end
    end

    class C2
    end

    module M
      refine Array do
        def deconstruct
          [0]
        end
      end

      refine Hash do
        def deconstruct_keys(_)
          {a: 0}
        end
      end

      refine C2.singleton_class do
        def ===(obj)
          obj.kind_of?(C1)
        end
      end
    end

    using M

    def test_refinements
      assert_block do
        case []
        in [0]
          true
        end
      end

      assert_block do
        case {}
        in {a: 0}
          true
        end
      end

      assert_block do
        case C1.new
        in C2(:C1)
          true
        end
      end
    end
  end

  ################################################################

  def test_struct
    assert_block do
      s = Struct.new(:a, :b)
      case s[0, 1]
      in 0, 1
        true
      end
    end

    s = Struct.new(:a, :b, keyword_init: true)
    assert_block do
      case s[a: 0, b: 1]
      in **r
        r == {a: 0, b: 1}
      end
    end
    assert_block do
      s = Struct.new(:a, :b, keyword_init: true)
      case s[a: 0, b: 1]
      in a:, b:
        a == 0 && b == 1
      end
    end
    assert_block do
      s = Struct.new(:a, :b, keyword_init: true)
      case s[a: 0, b: 1]
      in a:, c:
        raise a # suppress "unused variable: a" warning
        raise c # suppress "unused variable: c" warning
        flunk
      in a:, b:, c:
        flunk
      in b:
        b == 1
      end
    end
  end

  ################################################################

  def test_modifier_in
    1 in a
    assert_equal 1, a
    assert_raise(NoMatchingPatternError) do
      {a: 1} in {a: 0}
    end
    assert_syntax_error("if {} in {a:}; end", /void value expression/)
    assert_syntax_error(%q{
      1 in a, b
    }, /unexpected/, '[ruby-core:95098]')
    assert_syntax_error(%q{
      1 in a:
    }, /unexpected/, '[ruby-core:95098]')
  end

  def assert_experimental_warning(code)
    w = Warning[:experimental]

    Warning[:experimental] = false
    assert_warn('') {eval(code)}

    Warning[:experimental] = true
    assert_warn(/Pattern matching is experimental/) {eval(code)}
  ensure
    Warning[:experimental] = w
  end

  def test_experimental_warning
    assert_experimental_warning("case 0; in 0; end")
    assert_experimental_warning("0 in 0")
  end
end
END_of_GUARD
Warning[:experimental] = experimental
