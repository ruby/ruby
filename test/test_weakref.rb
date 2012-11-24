require 'test/unit'
require 'weakref'
require_relative './ruby/envutil'

class TestWeakRef < Test::Unit::TestCase
  def make_weakref(level = 10)
    obj = Object.new
    str = obj.to_s
    level.times {obj = WeakRef.new(obj)}
    return WeakRef.new(obj), str
  end

  def test_ref
    weak, str = make_weakref
    assert_equal(str, weak.to_s)
  end

  def test_recycled
    weak, str = make_weakref
    assert_nothing_raised(WeakRef::RefError) {weak.to_s}
    ObjectSpace.garbage_collect
    ObjectSpace.garbage_collect
    assert_raise(WeakRef::RefError) {weak.to_s}
  end

  def test_not_reference_different_object
    bug7304 = '[ruby-core:49044]'
    weakrefs = []
    3.times do
      obj = Object.new
      def obj.foo; end
      weakrefs << WeakRef.new(obj)
      ObjectSpace.garbage_collect
    end
    assert_nothing_raised(NoMethodError, bug7304) {
      weakrefs.each do |weak|
        begin
          weak.foo
        rescue WeakRef::RefError
        end
      end
    }
  end

  def test_weakref_finalize
    bug7304 = '[ruby-core:49044]'
    assert_normal_exit %q{
      require 'weakref'
      obj = Object.new
      3.times do
        WeakRef.new(obj)
        ObjectSpace.garbage_collect
      end
    }, bug7304
  end
end
