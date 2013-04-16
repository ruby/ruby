require 'test/unit'
require 'weakref'
require_relative './ruby/envutil'

class TestWeakRef < Test::Unit::TestCase
  def make_weakref
    obj = Object.new
    str = obj.to_s
    return WeakReference.new(obj), str
  end

  def test_ref
    weak, str = make_weakref
    assert_equal(str, weak.get.to_s)
  end

  def test_recycled
    weak, str = make_weakref
    assert_equal str, weak.get.to_s
    ObjectSpace.garbage_collect
    ObjectSpace.garbage_collect
    assert_equal nil, weak.get
  end

  def test_not_reference_different_object
    bug7304 = '[ruby-core:49044]'
    weakrefs = []
    3.times do
      obj = Object.new
      def obj.foo; end
      weakrefs << WeakReference.new(obj)
      ObjectSpace.garbage_collect
    end
    weakrefs.each do |weak|
      obj = weak.get
      assert obj == nil || obj.respond_to?(:foo)
    end
  end

  def test_weakref_finalize
    bug7304 = '[ruby-core:49044]'
    assert_normal_exit %q{
      require 'weakref'
      obj = Object.new
      3.times do
        WeakReference.new(obj)
        ObjectSpace.garbage_collect
      end
    }, bug7304
  end
end
