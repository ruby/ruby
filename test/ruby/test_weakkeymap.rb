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
    assert_weak_include(:key?, "foo")
    assert_not_send([@wm, :key?, "bar"])
  end

  def test_delete
    k1 = "foo"
    x1 = Object.new
    @wm[k1] = x1
    assert_equal x1, @wm[k1]
    assert_equal x1, @wm.delete(k1)
    assert_nil @wm[k1]
    assert_nil @wm.delete(k1)

    fallback =  @wm.delete(k1) do |key|
      assert_equal k1, key
      42
    end
    assert_equal 42, fallback
  end

  def test_clear
    k = "foo"
    @wm[k] = true
    assert @wm[k]
    assert_same @wm, @wm.clear
    refute @wm[k]
  end

  def test_clear_bug_20691
    assert_normal_exit(<<~RUBY)
      map = ObjectSpace::WeakKeyMap.new

      1_000.times do
        1_000.times do
          map[Object.new] = nil
        end

        map.clear
      end
    RUBY
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

  def test_compaction
    omit "compaction is not supported on this platform" unless GC.respond_to?(:compact)

    assert_separately(%w(-robjspace), <<-'end;')
      wm = ObjectSpace::WeakKeyMap.new
      key = Object.new
      val = Object.new
      wm[key] = val

      GC.verify_compaction_references(expand_heap: true, toward: :empty)

      assert_equal(val, wm[key])
    end;
  end

  def test_gc_compact_stress
    omit "compaction doesn't work well on s390x" if RUBY_PLATFORM =~ /s390x/ # https://github.com/ruby/ruby/pull/5077
    EnvUtil.under_gc_compact_stress { ObjectSpace::WeakKeyMap.new }
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
