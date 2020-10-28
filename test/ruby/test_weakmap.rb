# frozen_string_literal: false
require 'test/unit'

class TestWeakMap < Test::Unit::TestCase
  def setup
    @wm = ObjectSpace::WeakMap.new
  end

  def test_map
    x = Object.new
    k = "foo"
    @wm[k] = x
    assert_same(x, @wm[k])
    assert_not_same(x, @wm["FOO".downcase])
  end

  def test_aset_const
    x = Object.new
    @wm[true] = x
    assert_same(x, @wm[true])
    @wm[false] = x
    assert_same(x, @wm[false])
    @wm[nil] = x
    assert_same(x, @wm[nil])
    @wm[42] = x
    assert_same(x, @wm[42])
    @wm[:foo] = x
    assert_same(x, @wm[:foo])

    @wm[x] = true
    assert_same(true, @wm[x])
    @wm[x] = false
    assert_same(false, @wm[x])
    @wm[x] = nil
    assert_same(nil, @wm[x])
    @wm[x] = 42
    assert_same(42, @wm[x])
    @wm[x] = :foo
    assert_same(:foo, @wm[x])
  end

  def assert_weak_include(m, k, n = 100)
    if n > 0
      return assert_weak_include(m, k, n-1)
    end
    1.times do
      x = Object.new
      @wm[k] = x
      assert_send([@wm, m, k])
      assert_not_send([@wm, m, "FOO".downcase])
      x = Object.new
    end
  end

  def test_include?
    m = __callee__[/test_(.*)/, 1]
    k = "foo"
    1.times do
      assert_weak_include(m, k)
    end
    GC.start
    skip('TODO: failure introduced from r60440')
    assert_not_send([@wm, m, k])
  end
  alias test_member? test_include?
  alias test_key? test_include?

  def test_inspect
    x = Object.new
    k = BasicObject.new
    @wm[k] = x
    assert_match(/\A\#<#{@wm.class.name}:[^:]+:\s\#<BasicObject:[^:]*>\s=>\s\#<Object:[^:]*>>\z/,
                 @wm.inspect)
  end

  def test_each
    m = __callee__[/test_(.*)/, 1]
    x1 = Object.new
    k1 = "foo"
    @wm[k1] = x1
    x2 = Object.new
    k2 = "bar"
    @wm[k2] = x2
    n = 0
    @wm.__send__(m) do |k, v|
      assert_match(/\A(?:foo|bar)\z/, k)
      case k
      when /foo/
        assert_same(k1, k)
        assert_same(x1, v)
      when /bar/
        assert_same(k2, k)
        assert_same(x2, v)
      end
      n += 1
    end
    assert_equal(2, n)
  end

  def test_each_key
    x1 = Object.new
    k1 = "foo"
    @wm[k1] = x1
    x2 = Object.new
    k2 = "bar"
    @wm[k2] = x2
    n = 0
    @wm.each_key do |k|
      assert_match(/\A(?:foo|bar)\z/, k)
      case k
      when /foo/
        assert_same(k1, k)
      when /bar/
        assert_same(k2, k)
      end
      n += 1
    end
    assert_equal(2, n)
  end

  def test_each_value
    x1 = "foo"
    k1 = Object.new
    @wm[k1] = x1
    x2 = "bar"
    k2 = Object.new
    @wm[k2] = x2
    n = 0
    @wm.each_value do |v|
      assert_match(/\A(?:foo|bar)\z/, v)
      case v
      when /foo/
        assert_same(x1, v)
      when /bar/
        assert_same(x2, v)
      end
      n += 1
    end
    assert_equal(2, n)
  end

  def test_size
    m = __callee__[/test_(.*)/, 1]
    assert_equal(0, @wm.__send__(m))
    x1 = "foo"
    k1 = Object.new
    @wm[k1] = x1
    assert_equal(1, @wm.__send__(m))
    x2 = "bar"
    k2 = Object.new
    @wm[k2] = x2
    assert_equal(2, @wm.__send__(m))
  end
  alias test_length test_size

  def test_frozen_object
    o = Object.new.freeze
    assert_nothing_raised(FrozenError) {@wm[o] = 'foo'}
    assert_nothing_raised(FrozenError) {@wm['foo'] = o}
  end
end
