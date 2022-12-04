# frozen_string_literal: false
require 'test/unit'

# These test the functionality of object shapes
class TestShapes < Test::Unit::TestCase
  class ShapeOrder
    def initialize
      @b = :b # 5 => 6
    end

    def set_b
      @b = :b # 5 => 6
    end

    def set_c
      @c = :c # 5 => 7
    end
  end

  class Example
    def initialize
      @a = 1
    end
  end

  class RemoveAndAdd
    def add_foo
      @foo = 1
    end

    def remove
      remove_instance_variable(:@foo)
    end

    def add_bar
      @bar = 1
    end
  end

  # RubyVM::Shape.of returns new instances of shape objects for
  # each call. This helper method allows us to define equality for
  # shapes
  def assert_shape_equal(shape1, shape2)
    assert_equal(shape1.id, shape2.id)
    assert_equal(shape1.parent_id, shape2.parent_id)
    assert_equal(shape1.depth, shape2.depth)
    assert_equal(shape1.type, shape2.type)
  end

  def refute_shape_equal(shape1, shape2)
    refute_equal(shape1.id, shape2.id)
  end

  def test_shape_order
    bar = ShapeOrder.new # 0 => 1
    bar.set_c # 1 => 2
    bar.set_b # 2 => 2

    foo = ShapeOrder.new # 0 => 1
    shape_id = RubyVM::Shape.of(foo).id
    foo.set_b # should not transition
    assert_equal shape_id, RubyVM::Shape.of(foo).id
  end

  def test_iv_index
    example = RemoveAndAdd.new
    shape = RubyVM::Shape.of(example)
    assert_equal 0, shape.next_iv_index

    example.add_foo # makes a transition
    new_shape = RubyVM::Shape.of(example)
    assert_equal([:@foo], example.instance_variables)
    assert_equal(shape.id, new_shape.parent.id)
    assert_equal(1, new_shape.next_iv_index)

    example.remove # makes a transition
    remove_shape = RubyVM::Shape.of(example)
    assert_equal([], example.instance_variables)
    assert_equal(new_shape.id, remove_shape.parent.id)
    assert_equal(1, remove_shape.next_iv_index)

    example.add_bar # makes a transition
    bar_shape = RubyVM::Shape.of(example)
    assert_equal([:@bar], example.instance_variables)
    assert_equal(remove_shape.id, bar_shape.parent.id)
    assert_equal(2, bar_shape.next_iv_index)
  end

  class TestObject; end

  def test_new_obj_has_t_object_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of(TestObject.new).parent)
  end

  def test_str_has_root_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of(""))
  end

  def test_array_has_root_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of([]))
  end

  def test_hash_has_root_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of({}))
  end

  def test_true_has_special_const_shape_id
    assert_equal(RubyVM::Shape::SPECIAL_CONST_SHAPE_ID, RubyVM::Shape.of(true).id)
  end

  def test_nil_has_special_const_shape_id
    assert_equal(RubyVM::Shape::SPECIAL_CONST_SHAPE_ID, RubyVM::Shape.of(nil).id)
  end

  def test_basic_shape_transition
    obj = Example.new
    shape = RubyVM::Shape.of(obj)
    refute_equal(RubyVM::Shape.root_shape, shape)
    assert_equal :@a, shape.edge_name
    assert_equal RubyVM::Shape::SHAPE_IVAR, shape.type

    shape = shape.parent
    assert_equal RubyVM::Shape::SHAPE_T_OBJECT, shape.type

    shape = shape.parent
    assert_equal(RubyVM::Shape.root_shape.id, shape.id)
    assert_equal(obj.instance_variable_get(:@a), 1)
  end

  def test_different_objects_make_same_transition
    obj = []
    obj2 = ""
    obj.instance_variable_set(:@a, 1)
    obj2.instance_variable_set(:@a, 1)
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
  end

  def test_duplicating_objects
    obj = Example.new
    obj2 = obj.dup
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
  end

  def test_freezing_and_duplicating_object
    obj = Object.new.freeze
    obj2 = obj.dup
    refute_predicate(obj2, :frozen?)
    # dup'd objects shouldn't be frozen, and the shape should be the
    # parent shape of the copied object
    assert_equal(RubyVM::Shape.of(obj).parent.id, RubyVM::Shape.of(obj2).id)
  end

  def test_freezing_and_duplicating_object_with_ivars
    obj = Example.new.freeze
    obj2 = obj.dup
    refute_predicate(obj2, :frozen?)
    refute_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
    assert_equal(obj2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_duplicating_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    str2 = str.dup
    refute_predicate(str2, :frozen?)
    refute_equal(RubyVM::Shape.of(str).id, RubyVM::Shape.of(str2).id)
    assert_equal(str2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_cloning_objects
    obj = Object.new.freeze
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
  end

  def test_freezing_and_cloning_object_with_ivars
    obj = Example.new.freeze
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
    assert_equal(obj2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_cloning_string
    str = "str".freeze
    str2 = str.clone(freeze: true)
    assert_predicate(str2, :frozen?)
    assert_shape_equal(RubyVM::Shape.of(str), RubyVM::Shape.of(str2))
  end

  def test_freezing_and_cloning_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    str2 = str.clone(freeze: true)
    assert_predicate(str2, :frozen?)
    assert_shape_equal(RubyVM::Shape.of(str), RubyVM::Shape.of(str2))
    assert_equal(str2.instance_variable_get(:@a), 1)
  end

  def test_out_of_bounds_shape
    assert_raise ArgumentError do
      RubyVM::Shape.find_by_id(RubyVM::Shape.next_shape_id)
    end
    assert_raise ArgumentError do
      RubyVM::Shape.find_by_id(-1)
    end
  end
end if defined?(RubyVM::Shape)
