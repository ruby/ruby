require 'test/unit'
require 'weak'
require_relative '../ruby/envutil'

class TestWeakRef < Test::Unit::TestCase
  def make_weakref(*args, level: 10)
    if level > 0
      make_weakref(*args, level: level-1)
    else
      args <<= Object.new if args.empty?
      Weak.ref(*args)
    end
  ensure
    args.clear
  end

  def test_ref
    obj = Object.new
    weak = Weak.ref(obj)
    assert_same(obj, weak.get)
    assert_predicate(weak, :alive?)
  end

  def test_recycled
    weak = 1.times {break make_weakref}
    GC.start
    GC.start
    assert_nil(weak.get)
    assert_not_predicate(weak, :alive?)
  end

  def test_finalize
    bug7304 = '[ruby-core:49044]'
    assert_normal_exit %q{
      require 'weak'
      obj = Object.new
      3.times do
        Weak.ref(obj)
        ObjectSpace.garbage_collect
      end
    }, bug7304
  end

  def test_queue
    q = Object.new
    def q.pushed; @pushed; end
    def q.push(obj); @pushed = obj; end

    ref = nil
    1.times do
      o = Object.new
      ref = make_weakref(o, q)
      assert_same(o, ref.get)
      assert_nil(q.pushed)
    end

    5.times { GC.start }
    assert_nil(ref.get)
    assert_same(ref, q.pushed)
  end
end
