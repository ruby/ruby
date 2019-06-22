# frozen_string_literal: false
require 'test/unit'

class TestWeakMap < Test::Unit::TestCase
  def setup
    @wm = ObjectSpace::WeakMap.new
  end

  def test_dead_reference
    weaks = []
    100.times do
      key = Object.new
      weaks << key
      make_weakref @wm, key
      ObjectSpace.garbage_collect
      ObjectSpace.garbage_collect
      weak = weaks.map { |k| @wm[k] }.grep(ObjectSpace::WeakMap::DeadRef).first
      # Found a dead reference
      return assert(true) if weak
    end

    flunk "couldn't find a dead reference"
  end

  def test_special_values
    weaks = []
    objs = [true, false, nil, 1, 0.2]
    objs.each do |v|
      k = Object.new
      weaks << k
      @wm[k] = v
    end
    assert_equal objs, @wm.values
  end

  def test_special_each_values
    weaks = []
    objs = [true, false, nil, 1, 0.2]
    objs.each do |v|
      k = Object.new
      weaks << k
      @wm[k] = v
    end
    m = []
    @wm.each_value { |z| m << z }
    assert_equal objs, m
  end

  def test_special_each
    weaks = []
    objs = [true, false, nil, 1, 0.2]
    objs.each do |v|
      k = Object.new
      weaks << k
      @wm[k] = v
    end
    m = []
    @wm.each { |_, z| m << z }
    assert_equal objs, m
  end

  def test_special_each_key
    weaks = []
    objs = [true, false, nil, 1, 0.2]
    objs.each do |v|
      k = Object.new
      weaks << k
      @wm[k] = v
    end
    m = []
    @wm.each_key { |z| m << z }
    assert_equal weaks, m
  end

  def test_special_keys
    weaks = []
    objs = [true, false, nil, 1, 0.2]
    objs.each do |v|
      k = Object.new
      weaks << k
      @wm[k] = v
    end
    assert_equal weaks, @wm.keys
  end

  def make_weakref(wm, key, level = 10)
    if level > 0
      make_weakref(wm, key, level - 1)
    else
      wm[key] = Object.new
    end
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
    assert_raise(ArgumentError) {@wm[true] = x}
    assert_raise(ArgumentError) {@wm[false] = x}
    assert_raise(ArgumentError) {@wm[nil] = x}
    assert_raise(ArgumentError) {@wm[42] = x}
    assert_raise(ArgumentError) {@wm[:foo] = x}
    assert @wm[x] = true
    assert_equal false,  @wm[x] = false
    assert_nil @wm[x] = nil
    assert_equal 42, @wm[x] = 42
    assert_equal :foo, @wm[x] = :foo
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
end
