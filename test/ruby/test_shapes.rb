# frozen_string_literal: false
require 'test/unit'

# These test the functionality of object shapes
class TestShapes < Test::Unit::TestCase
  class Example
    def initialize
      @a = 1
    end
  end

  # RubyVM.debug_shape returns new instances of shape objects for
  # each call. This helper method allows us to define equality for
  # shapes
  def assert_shape_equal(shape1, shape2)
    assert_equal(shape1.id, shape2.id)
    assert_equal(shape1.parent_id, shape2.parent_id)
    assert_equal(shape1.depth, shape2.depth)
  end

  def refute_shape_equal(shape1, shape2)
    refute_equal(shape1.id, shape2.id)
  end

  def test_new_obj_has_root_shape
    assert_shape_equal(RubyVM.debug_root_shape, RubyVM.debug_shape(Object.new))
  end

  def test_frozen_new_obj_has_frozen_root_shape
    assert_shape_equal(
      RubyVM.debug_frozen_root_shape,
      RubyVM.debug_shape(Object.new.freeze)
    )
  end

  def test_str_has_root_shape
    assert_shape_equal(RubyVM.debug_root_shape, RubyVM.debug_shape(""))
  end

  def test_array_has_root_shape
    assert_shape_equal(RubyVM.debug_root_shape, RubyVM.debug_shape([]))
  end

  def test_hash_has_root_shape
    assert_shape_equal(RubyVM.debug_root_shape, RubyVM.debug_shape({}))
  end

  def test_true_has_frozen_root_shape
    assert_shape_equal(RubyVM.debug_frozen_root_shape, RubyVM.debug_shape(true))
  end

  def test_nil_has_frozen_root_shape
    assert_shape_equal(RubyVM.debug_frozen_root_shape, RubyVM.debug_shape(nil))
  end

  def test_basic_shape_transition
    obj = Example.new
    refute_equal(RubyVM.debug_root_shape, RubyVM.debug_shape(obj))
    assert_shape_equal(RubyVM.debug_root_shape.edges[:@a], RubyVM.debug_shape(obj))
    assert_equal(obj.instance_variable_get(:@a), 1)
  end

  def test_different_objects_make_same_transition
    obj = Example.new
    obj2 = ""
    obj2.instance_variable_set(:@a, 1)
    assert_shape_equal(RubyVM.debug_shape(obj), RubyVM.debug_shape(obj2))
  end

  def test_duplicating_objects
    obj = Example.new
    obj2 = obj.dup
    assert_shape_equal(RubyVM.debug_shape(obj), RubyVM.debug_shape(obj2))
  end

  def test_freezing_and_duplicating_object
    obj = Object.new.freeze
    obj2 = obj.dup
    refute_predicate(obj2, :frozen?)
    refute_equal(RubyVM.debug_shape(obj).id, RubyVM.debug_shape(obj2).id)
  end

  def test_freezing_and_duplicating_object_with_ivars
    obj = Example.new.freeze
    obj2 = obj.dup
    refute_predicate(obj2, :frozen?)
    refute_shape_equal(RubyVM.debug_shape(obj), RubyVM.debug_shape(obj2))
    assert_equal(obj2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_duplicating_string
    str = "str".freeze
    str2 = str.dup
    refute_predicate(str2, :frozen?)
    refute_equal(RubyVM.debug_shape(str).id, RubyVM.debug_shape(str2).id)
  end

  def test_freezing_and_duplicating_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    str2 = str.dup
    refute_predicate(str2, :frozen?)
    refute_equal(RubyVM.debug_shape(str).id, RubyVM.debug_shape(str2).id)
    assert_equal(str2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_cloning_objects
    obj = Object.new.freeze
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    assert_shape_equal(RubyVM.debug_shape(obj), RubyVM.debug_shape(obj2))
  end

  def test_freezing_and_cloning_object_with_ivars
    obj = Example.new.freeze
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    assert_shape_equal(RubyVM.debug_shape(obj), RubyVM.debug_shape(obj2))
    assert_equal(obj2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_cloning_string
    str = "str".freeze
    str2 = str.clone(freeze: true)
    assert_predicate(str2, :frozen?)
    assert_shape_equal(RubyVM.debug_shape(str), RubyVM.debug_shape(str2))
  end

  def test_freezing_and_cloning_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    str2 = str.clone(freeze: true)
    assert_predicate(str2, :frozen?)
    assert_shape_equal(RubyVM.debug_shape(str), RubyVM.debug_shape(str2))
    assert_equal(str2.instance_variable_get(:@a), 1)
  end
end
