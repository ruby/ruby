# frozen_string_literal: false
require 'test/unit'

# These test the functionality of object shapes
class TestShapes < Test::Unit::TestCase
  class IVOrder
    def expected_ivs
      %w{ @a @b @c @d @e @f @g @h @i @j @k }
    end

    def set_ivs
      expected_ivs.each { instance_variable_set(_1, 1) }
      self
    end
  end

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

    def remove_foo
      remove_instance_variable(:@foo)
    end

    def add_bar
      @bar = 1
    end
  end

  class TooComplex
    attr_reader :hopefully_unique_name, :b

    def initialize
      @hopefully_unique_name = "a"
      @b = "b"
    end

    # Make enough lazily defined accessors to allow us to force
    # polymorphism
    class_eval (RubyVM::Shape::SHAPE_MAX_VARIATIONS + 1).times.map {
      "def a#{_1}_m; @a#{_1} ||= #{_1}; end"
    }.join(" ; ")

    class_eval "attr_accessor " + (RubyVM::Shape::SHAPE_MAX_VARIATIONS + 1).times.map {
      ":a#{_1}"
    }.join(", ")

    def iv_not_defined; @not_defined; end

    def write_iv_method
      self.a3 = 12345
    end

    def write_iv
      @a3 = 12345
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

  def test_iv_order_correct_on_complex_objects
    (RubyVM::Shape::SHAPE_MAX_VARIATIONS + 1).times {
      IVOrder.new.instance_variable_set("@a#{_1}", 1)
    }

    obj = IVOrder.new
    iv_list = obj.set_ivs.instance_variables
    assert_equal obj.expected_ivs, iv_list.map(&:to_s)
  end

  def test_too_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
  end

  def test_too_complex_ractor
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      class TooComplex
        attr_reader :very_unique
      end

      RubyVM::Shape::SHAPE_MAX_VARIATIONS.times do
        TooComplex.new.instance_variable_set(:"@unique_#{_1}", Object.new)
      end

      tc = TooComplex.new
      tc.instance_variable_set(:"@very_unique", 3)

      assert_predicate RubyVM::Shape.of(tc), :too_complex?
      assert_equal 3, tc.very_unique
      assert_equal 3, Ractor.new(tc) { |x| Ractor.yield(x.very_unique) }.take
      assert_equal tc.instance_variables.sort, Ractor.new(tc) { |x| Ractor.yield(x.instance_variables) }.take.sort
    end;
  end

  def test_too_complex_ractor_shareable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      class TooComplex
        attr_reader :very_unique
      end

      RubyVM::Shape::SHAPE_MAX_VARIATIONS.times do
        TooComplex.new.instance_variable_set(:"@unique_#{_1}", Object.new)
      end

      tc = TooComplex.new
      tc.instance_variable_set(:"@very_unique", 3)

      assert_predicate RubyVM::Shape.of(tc), :too_complex?
      assert_equal 3, tc.very_unique
      assert_equal 3, Ractor.make_shareable(tc).very_unique
    end;
  end

  def test_read_iv_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    assert_equal 3, tc.a3_m
  end

  def test_read_method_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    assert_equal 3, tc.a3_m
    assert_equal 3, tc.a3
  end

  def test_write_method_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    tc.write_iv_method
    tc.write_iv_method
    assert_equal 12345, tc.a3_m
    assert_equal 12345, tc.a3
  end

  def test_write_iv_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    tc.write_iv
    tc.write_iv
    assert_equal 12345, tc.a3_m
    assert_equal 12345, tc.a3
  end

  def test_iv_read_via_method_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    assert_equal 3, tc.a3_m
    assert_equal 3, tc.instance_variable_get(:@a3)
  end

  def test_delete_iv_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?

    assert_equal 3, tc.a3_m # make sure IV is initialized
    assert tc.instance_variable_defined?(:@a3)
    tc.remove_instance_variable(:@a3)
    assert_nil tc.a3
  end

  def test_delete_undefined_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?

    refute tc.instance_variable_defined?(:@a3)
    assert_raise(NameError) do
      tc.remove_instance_variable(:@a3)
    end
    assert_nil tc.a3
  end

  def test_freeze_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    tc.freeze
    assert_raise(FrozenError) { tc.a3_m }
  end

  def test_read_undefined_iv_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    assert_equal nil, tc.iv_not_defined
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
    initial_shape = RubyVM::Shape.of(example)
    assert_equal 0, initial_shape.next_iv_index

    example.add_foo # makes a transition
    add_foo_shape = RubyVM::Shape.of(example)
    assert_equal([:@foo], example.instance_variables)
    assert_equal(initial_shape.id, add_foo_shape.parent.id)
    assert_equal(1, add_foo_shape.next_iv_index)

    example.remove_foo # makes a transition
    remove_foo_shape = RubyVM::Shape.of(example)
    assert_equal([], example.instance_variables)
    assert_shape_equal(initial_shape, remove_foo_shape)

    example.add_bar # makes a transition
    bar_shape = RubyVM::Shape.of(example)
    assert_equal([:@bar], example.instance_variables)
    assert_equal(initial_shape.id, bar_shape.parent_id)
    assert_equal(1, bar_shape.next_iv_index)
  end

  def test_remove_then_add_again
    example = RemoveAndAdd.new
    _initial_shape = RubyVM::Shape.of(example)

    example.add_foo # makes a transition
    add_foo_shape = RubyVM::Shape.of(example)
    example.remove_foo # makes a transition
    example.add_foo # makes a transition
    assert_shape_equal(add_foo_shape, RubyVM::Shape.of(example))
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
      RubyVM::Shape.find_by_id(RubyVM.stat[:next_shape_id])
    end
    assert_raise ArgumentError do
      RubyVM::Shape.find_by_id(-1)
    end
  end

  def ensure_complex
    RubyVM::Shape::SHAPE_MAX_VARIATIONS.times do
      tc = TooComplex.new
      tc.send("a#{_1}_m")
    end
  end
end if defined?(RubyVM::Shape)
