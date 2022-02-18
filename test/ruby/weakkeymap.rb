# frozen_string_literal: false
require 'test/unit'

class TestWeakKeyMap < Test::Unit::TestCase
  def setup
    @wm = ObjectSpace::WeakKeyMap.new
  end

  def test_map
    x = Object.new
    k = "foo"
    @wm[k] = x
    assert_same(x, @wm[k])
    assert_same(x, @wm["FOO".downcase])
  end

  def test_aset_const
    x = Object.new
    assert_raise(ArgumentError) { @wm[true] = x }
    assert_raise(ArgumentError) { @wm[false] = x }
    assert_raise(ArgumentError) { @wm[nil] = x }
    assert_raise(ArgumentError) { @wm[42] = x }
    assert_raise(ArgumentError) { @wm[2**128] = x }
    assert_raise(ArgumentError) { @wm[1.23] = x }
    assert_raise(ArgumentError) { @wm[:foo] = x }
    assert_raise(ArgumentError) { @wm["foo#{rand}".to_sym] = x }
  end

  def test_getkey
    k = "foo"
    @wm[k] = true
    assert_same(k, @wm.getkey("FOO".downcase))
  end

  def test_key?
    1.times do
      assert_weak_include(:key?, "foo")
    end
    GC.start
    assert_not_send([@wm, :key?, "FOO".downcase])
  end

  def test_clear
    k = "foo"
    @wm[k] = true
    assert @wm[k]
    assert_same @wm, @wm.clear
    refute @wm[k]
  end

  def test_inspect
    x = Object.new
    k = Object.new
    @wm[k] = x
    assert_match(/\A\#<#{@wm.class.name}:[\dxa-f]+ size=\d+>\z/, @wm.inspect)

    1000.times do |i|
      @wm[i.to_s] = Object.new
      @wm.inspect
    end
    assert_match(/\A\#<#{@wm.class.name}:[\dxa-f]+ size=\d+>\z/, @wm.inspect)
  end

  def test_no_hash_method
    k = BasicObject.new
    assert_raise NoMethodError do
      @wm[k] = 42
    end
  end

  def test_frozen_object
    o = Object.new.freeze
    assert_nothing_raised(FrozenError) {@wm[o] = 'foo'}
    assert_nothing_raised(FrozenError) {@wm['foo'] = o}
  end

  def test_inconsistent_hash_key
    assert_no_memory_leak [], '', <<~RUBY
      class BadHash
        def initialize
          @hash = 0
        end

        def hash
          @hash += 1
        end
      end

      k = BadHash.new
      wm = ObjectSpace::WeakKeyMap.new

      100_000.times do |i|
        wm[k] = i
      end
    RUBY
  end

  private

  def assert_weak_include(m, k, n = 100)
    if n > 0
      return assert_weak_include(m, k, n-1)
    end
    1.times do
      x = Object.new
      @wm[k] = x
      assert_send([@wm, m, k])
      assert_send([@wm, m, "FOO".downcase])
      x = Object.new
    end
  end
end
