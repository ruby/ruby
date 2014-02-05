require 'test/unit'
require 'weakref'
require_relative './ruby/envutil'

class TestWeakRef < Test::Unit::TestCase
  def make_weakref(level = 10)
    if level > 0
      make_weakref(level - 1)
    else
      WeakRef.new(Object.new)
    end
  end

  def test_ref
    obj = Object.new
    weak = WeakRef.new(obj)
    assert_equal(obj.to_s, weak.to_s)
    assert_predicate(weak, :weakref_alive?)
  end

  def test_recycled
    weaks = []
    weak = nil
    100.times do
      weaks << make_weakref
      ObjectSpace.garbage_collect
      ObjectSpace.garbage_collect
      break if weak = weaks.find {|w| !w.weakref_alive?}
    end
    assert_raise(WeakRef::RefError) {weak.to_s}
    assert_not_predicate(weak, :weakref_alive?)
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
