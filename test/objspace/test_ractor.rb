require "test/unit"
require "objspace"

class TestObjSpaceRactor < Test::Unit::TestCase
  def test_tracing_does_not_crash
    assert_ractor(<<~RUBY, require: 'objspace')
      ObjectSpace.trace_object_allocations do
        r = Ractor.new do
          _obj = 'a' * 1024
        end

        r.join
      end
    RUBY
  end

  def test_undefine_finalizer
    assert_ractor(<<~'RUBY', require: 'objspace')
      def fin
        ->(id) { }
      end
      ractors = 5.times.map do
        Ractor.new do
          10_000.times do
            o = Object.new
            ObjectSpace.define_finalizer(o, fin)
            ObjectSpace.undefine_finalizer(o)
          end
        end
      end

      ractors.each(&:join)
    RUBY
  end

  def test_copy_finalizer
    assert_ractor(<<~'RUBY', require: 'objspace')
      def fin
        ->(id) { }
      end
      OBJ = Object.new
      ObjectSpace.define_finalizer(OBJ, fin)
      OBJ.freeze

      ractors = 5.times.map do
        Ractor.new do
          10_000.times do
            OBJ.clone
          end
        end
      end

      ractors.each(&:join)
    RUBY
  end

  def test_find_paths_to_unshareable_objects
    # Direct shareable object
    assert_equal([], ObjectSpace.find_paths_to_unshareable_objects(1).to_a)

    # Direct unshareable object
    assert_equal([["unfrozen"]], ObjectSpace.find_paths_to_unshareable_objects("unfrozen").to_a)

    # Hash containing unshareable object
    obj = { a: 1, b: "frozen".freeze, c: "unfrozen" }
    paths = ObjectSpace.find_paths_to_unshareable_objects(obj).to_a
    assert_include(paths, [obj])
    assert_include(paths, [obj, "unfrozen"])

    # Array containing unshareable object
    obj = [1, 2, "unfrozen", "frozen".freeze]
    paths = ObjectSpace.find_paths_to_unshareable_objects(obj).to_a
    assert_include(paths, [obj])
    assert_include(paths, [obj, "unfrozen"])

    # Custom class
    klass = Class.new do
      attr_accessor :value
    end
    obj = klass.new
    obj.value = "unfrozen"
    paths = ObjectSpace.find_paths_to_unshareable_objects(obj).to_a
    assert_include(paths, [obj])
    assert_include(paths, [obj, "unfrozen"])

    # Circular reference
    obj1 = { name: "obj1" }
    obj2 = { name: "obj2", ref: obj1 }
    obj1[:ref] = obj2
    paths = ObjectSpace.find_paths_to_unshareable_objects(obj1).to_a
    assert_include(paths, [obj1, obj2, "obj2"]) # does not circle back to obj1
  end
end
