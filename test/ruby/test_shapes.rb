# frozen_string_literal: false
require 'test/unit'
require 'objspace'
require 'json'

# These test the functionality of object shapes
class TestShapes < Test::Unit::TestCase
  MANY_IVS = 80

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

  class OrderedAlloc
    def add_ivars
      10.times do |i|
        instance_variable_set("@foo" + i.to_s, 0)
      end
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

  def test_ordered_alloc_is_not_complex
    5.times { OrderedAlloc.new.add_ivars }
    obj = JSON.parse(ObjectSpace.dump(OrderedAlloc))
    assert_operator obj["variation_count"], :<, RubyVM::Shape::SHAPE_MAX_VARIATIONS
  end

  def test_too_many_ivs_on_obj
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Hi; end

      RubyVM::Shape.exhaust_shapes(2)

      obj = Hi.new
      obj.instance_variable_set(:@b, 1)
      obj.instance_variable_set(:@c, 1)
      obj.instance_variable_set(:@d, 1)

      assert_predicate RubyVM::Shape.of(obj), :too_complex?
    end;
  end

  def test_too_many_ivs_on_class
    obj = Class.new

    (MANY_IVS + 1).times do
      obj.instance_variable_set(:"@a#{_1}", 1)
    end

    assert_false RubyVM::Shape.of(obj).too_complex?
  end

  def test_removing_when_too_many_ivs_on_class
    obj = Class.new

    (MANY_IVS + 2).times do
      obj.instance_variable_set(:"@a#{_1}", 1)
    end
    (MANY_IVS + 2).times do
      obj.remove_instance_variable(:"@a#{_1}")
    end

    assert_empty obj.instance_variables
  end

  def test_removing_when_too_many_ivs_on_module
    obj = Module.new

    (MANY_IVS + 2).times do
      obj.instance_variable_set(:"@a#{_1}", 1)
    end
    (MANY_IVS + 2).times do
      obj.remove_instance_variable(:"@a#{_1}")
    end

    assert_empty obj.instance_variables
  end

  def test_too_complex_geniv
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class TooComplex < Hash
        attr_reader :very_unique
      end

      RubyVM::Shape.exhaust_shapes

      (RubyVM::Shape::SHAPE_MAX_VARIATIONS * 2).times do
        TooComplex.new.instance_variable_set(:"@unique_#{_1}", 1)
      end

      tc = TooComplex.new
      tc.instance_variable_set(:@very_unique, 3)
      tc.instance_variable_set(:@very_unique2, 4)
      assert_equal 3, tc.instance_variable_get(:@very_unique)
      assert_equal 4, tc.instance_variable_get(:@very_unique2)

      assert_equal [:@very_unique, :@very_unique2], tc.instance_variables
    end;
  end

  def test_use_all_shapes_then_freeze
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Hi; end
      RubyVM::Shape.exhaust_shapes(3)

      obj = Hi.new
      i = 0
      while RubyVM::Shape.shapes_available > 0
        obj.instance_variable_set(:"@b#{i}", 1)
        i += 1
      end
      obj.freeze

      assert obj.frozen?
    end;
  end

  def test_run_out_of_shape_for_object
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class A
        def initialize
          @a = 1
        end
      end
      RubyVM::Shape.exhaust_shapes

      A.new
    end;
  end

  def test_run_out_of_shape_for_class_ivar
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM::Shape.exhaust_shapes

      c = Class.new
      c.instance_variable_set(:@a, 1)
      assert_equal(1, c.instance_variable_get(:@a))

      c.remove_instance_variable(:@a)
      assert_nil(c.instance_variable_get(:@a))

      assert_raise(NameError) do
        c.remove_instance_variable(:@a)
      end
    end;
  end

  def test_evacuate_class_ivar_and_compaction
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      count = 20

      c = Class.new
      count.times do |ivar|
        c.instance_variable_set("@i#{ivar}", "ivar-#{ivar}")
      end

      RubyVM::Shape.exhaust_shapes

      GC.auto_compact = true
      GC.stress = true
      # Cause evacuation
      c.instance_variable_set(:@a, o = Object.new)
      assert_equal(o, c.instance_variable_get(:@a))
      GC.stress = false

      count.times do |ivar|
        assert_equal "ivar-#{ivar}", c.instance_variable_get("@i#{ivar}")
      end
    end;
  end

  def test_evacuate_generic_ivar_and_compaction
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      count = 20

      c = Hash.new
      count.times do |ivar|
        c.instance_variable_set("@i#{ivar}", "ivar-#{ivar}")
      end

      RubyVM::Shape.exhaust_shapes

      GC.auto_compact = true
      GC.stress = true

      # Cause evacuation
      c.instance_variable_set(:@a, o = Object.new)
      assert_equal(o, c.instance_variable_get(:@a))

      GC.stress = false

      count.times do |ivar|
        assert_equal "ivar-#{ivar}", c.instance_variable_get("@i#{ivar}")
      end
    end;
  end

  def test_evacuate_object_ivar_and_compaction
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      count = 20

      c = Object.new
      count.times do |ivar|
        c.instance_variable_set("@i#{ivar}", "ivar-#{ivar}")
      end

      RubyVM::Shape.exhaust_shapes

      GC.auto_compact = true
      GC.stress = true

      # Cause evacuation
      c.instance_variable_set(:@a, o = Object.new)
      assert_equal(o, c.instance_variable_get(:@a))

      GC.stress = false

      count.times do |ivar|
        assert_equal "ivar-#{ivar}", c.instance_variable_get("@i#{ivar}")
      end
    end;
  end

  def test_gc_stress_during_evacuate_generic_ivar
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      [].instance_variable_set(:@a, 1)

      RubyVM::Shape.exhaust_shapes

      ary = 10.times.map { [] }

      GC.stress = true
      ary.each do |o|
        o.instance_variable_set(:@a, 1)
        o.instance_variable_set(:@b, 1)
      end
    end;
  end

  def test_run_out_of_shape_for_module_ivar
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM::Shape.exhaust_shapes

      module Foo
        @a = 1
        @b = 2
        assert_equal 1, @a
        assert_equal 2, @b
      end
    end;
  end

  def test_run_out_of_shape_for_class_cvar
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM::Shape.exhaust_shapes

      c = Class.new

      c.class_variable_set(:@@a, 1)
      assert_equal(1, c.class_variable_get(:@@a))

      c.class_eval { remove_class_variable(:@@a) }
      assert_false(c.class_variable_defined?(:@@a))

      assert_raise(NameError) do
        c.class_eval { remove_class_variable(:@@a) }
      end
    end;
  end

  def test_run_out_of_shape_generic_instance_variable_set
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class TooComplex < Hash
      end

      RubyVM::Shape.exhaust_shapes

      tc = TooComplex.new
      tc.instance_variable_set(:@a, 1)
      tc.instance_variable_set(:@b, 2)

      tc.remove_instance_variable(:@a)
      assert_nil(tc.instance_variable_get(:@a))

      assert_raise(NameError) do
        tc.remove_instance_variable(:@a)
      end
    end;
  end

  def test_run_out_of_shape_generic_ivar_set
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Hi < String
        def initialize
          8.times do |i|
            instance_variable_set("@ivar_#{i}", i)
          end
        end

        def transition
          @hi_transition ||= 1
        end
      end

      a = Hi.new

      # Try to run out of shapes
      RubyVM::Shape.exhaust_shapes

      assert_equal 1, a.transition
      assert_equal 1, a.transition
    end;
  end

  def test_run_out_of_shape_instance_variable_defined
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class A
        attr_reader :a, :b, :c, :d
        def initialize
          @a = @b = @c = @d = 1
        end
      end

      RubyVM::Shape.exhaust_shapes

      a = A.new
      assert_equal true, a.instance_variable_defined?(:@a)
    end;
  end

  def test_run_out_of_shape_instance_variable_defined_on_module
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM::Shape.exhaust_shapes

      module A
        @a = @b = @c = @d = 1
      end

      assert_equal true, A.instance_variable_defined?(:@a)
    end;
  end

  def test_run_out_of_shape_during_remove_instance_variable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      o = Object.new
      10.times { |i| o.instance_variable_set(:"@a#{i}", i) }

      RubyVM::Shape.exhaust_shapes

      o.remove_instance_variable(:@a0)
      (1...10).each do |i|
        assert_equal(i, o.instance_variable_get(:"@a#{i}"))
      end
    end;
  end

  def test_run_out_of_shape_remove_instance_variable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class A
        attr_reader :a, :b, :c, :d
        def initialize
          @a = @b = @c = @d = 1
        end
      end

      a = A.new

      RubyVM::Shape.exhaust_shapes

      a.remove_instance_variable(:@b)
      assert_nil a.b

      a.remove_instance_variable(:@a)
      assert_nil a.a

      a.remove_instance_variable(:@c)
      assert_nil a.c

      assert_equal 1, a.d
    end;
  end

  def test_run_out_of_shape_rb_obj_copy_ivar
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class A
        def initialize
          init # Avoid right sizing
        end

        def init
          @a = @b = @c = @d = @e = @f = 1
        end
      end

      a = A.new

      RubyVM::Shape.exhaust_shapes

      a.dup
    end;
  end

  def test_evacuate_generic_ivar_memory_leak
    assert_no_memory_leak([], "#{<<~'begin;'}", "#{<<~'end;'}", rss: true)
      o = []
      o.instance_variable_set(:@a, 1)

      RubyVM::Shape.exhaust_shapes

      ary = 1_000_000.times.map { [] }
    begin;
      ary.each do |o|
        o.instance_variable_set(:@a, 1)
        o.instance_variable_set(:@b, 1)
      end
      ary.clear
      ary = nil
      GC.start
    end;
  end

  def test_use_all_shapes_module
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Hi; end

      RubyVM::Shape.exhaust_shapes(2)

      obj = Module.new
      3.times do
        obj.instance_variable_set(:"@a#{_1}", _1)
      end

      ivs = 3.times.map do
        obj.instance_variable_get(:"@a#{_1}")
      end

      assert_equal [0, 1, 2], ivs
    end;
  end

  def test_complex_freeze_after_clone
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Hi; end

      RubyVM::Shape.exhaust_shapes(2)

      obj = Object.new
      i = 0
      while RubyVM::Shape.shapes_available > 0
        obj.instance_variable_set(:"@b#{i}", i)
        i += 1
      end

      v = obj.clone(freeze: true)
      assert_predicate v, :frozen?
      assert_equal 0, v.instance_variable_get(:@b0)
    end;
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

  def test_too_complex_and_frozen
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

      shape = RubyVM::Shape.of(tc)
      assert_predicate shape, :too_complex?
      refute_predicate shape, :shape_frozen?
      tc.freeze
      frozen_shape = RubyVM::Shape.of(tc)
      refute_equal shape.id, frozen_shape.id
      assert_predicate frozen_shape, :too_complex?
      assert_predicate frozen_shape, :shape_frozen?

      assert_equal 3, tc.very_unique
      assert_equal 3, Ractor.make_shareable(tc).very_unique
    end;
  end

  def test_too_complex_and_frozen_and_object_id
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

      shape = RubyVM::Shape.of(tc)
      assert_predicate shape, :too_complex?
      refute_predicate shape, :shape_frozen?
      tc.freeze
      frozen_shape = RubyVM::Shape.of(tc)
      refute_equal shape.id, frozen_shape.id
      assert_predicate frozen_shape, :too_complex?
      assert_predicate frozen_shape, :shape_frozen?
      refute_predicate frozen_shape, :has_object_id?

      tc.object_id

      id_shape = RubyVM::Shape.of(tc)
      refute_equal frozen_shape.id, id_shape.id
      assert_predicate id_shape, :too_complex?
      assert_predicate id_shape, :shape_frozen?
      assert_predicate id_shape, :has_object_id?

      assert_equal 3, tc.very_unique
      assert_equal 3, Ractor.make_shareable(tc).very_unique
    end;
  end

  def test_too_complex_obj_ivar_ractor_share
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil

      RubyVM::Shape.exhaust_shapes

      r = Ractor.new do
        o = Object.new
        o.instance_variable_set(:@a, "hello")
        Ractor.yield(o)
      end

      o = r.take
      assert_equal "hello", o.instance_variable_get(:@a)
    end;
  end

  def test_too_complex_generic_ivar_ractor_share
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil

      RubyVM::Shape.exhaust_shapes

      r = Ractor.new do
        o = []
        o.instance_variable_set(:@a, "hello")
        Ractor.yield(o)
      end

      o = r.take
      assert_equal "hello", o.instance_variable_get(:@a)
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

  def test_remove_instance_variable
    ivars_count = 5
    object = Object.new
    ivars_count.times do |i|
      object.instance_variable_set("@ivar_#{i}", i)
    end

    ivars = ivars_count.times.map do |i|
      object.instance_variable_get("@ivar_#{i}")
    end
    assert_equal [0, 1, 2, 3, 4], ivars

    object.remove_instance_variable(:@ivar_2)

    ivars = ivars_count.times.map do |i|
      object.instance_variable_get("@ivar_#{i}")
    end
    assert_equal [0, 1, nil, 3, 4], ivars
  end

  def test_remove_instance_variable_when_out_of_shapes
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      ivars_count = 5
      object = Object.new
      ivars_count.times do |i|
        object.instance_variable_set("@ivar_#{i}", i)
      end

      ivars = ivars_count.times.map do |i|
        object.instance_variable_get("@ivar_#{i}")
      end
      assert_equal [0, 1, 2, 3, 4], ivars

      RubyVM::Shape.exhaust_shapes

      object.remove_instance_variable(:@ivar_2)

      ivars = ivars_count.times.map do |i|
        object.instance_variable_get("@ivar_#{i}")
      end
      assert_equal [0, 1, nil, 3, 4], ivars
    end;
  end

  def test_remove_instance_variable_capacity_transition
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      t_object_shape = RubyVM::Shape.find_by_id(RubyVM::Shape::FIRST_T_OBJECT_SHAPE_ID)
      assert_equal(RubyVM::Shape::SHAPE_T_OBJECT, t_object_shape.type)

      initial_capacity = t_object_shape.capacity

      # a does not transition in capacity
      a = Class.new.new
      initial_capacity.times do |i|
        a.instance_variable_set(:"@ivar#{i + 1}", i)
      end

      # b transitions in capacity
      b = Class.new.new
      (initial_capacity + 1).times do |i|
        b.instance_variable_set(:"@ivar#{i}", i)
      end

      assert_operator(RubyVM::Shape.of(a).capacity, :<, RubyVM::Shape.of(b).capacity)

      # b will now have the same tree as a
      b.remove_instance_variable(:@ivar0)

      a.instance_variable_set(:@foo, 1)
      a.instance_variable_set(:@bar, 1)

      # Check that there is no heap corruption
      GC.verify_internal_consistency
    end;
  end

  def test_freeze_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    tc.freeze
    assert_raise(FrozenError) { tc.a3_m }
    # doesn't transition to frozen shape in this case
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
  end

  def test_read_undefined_iv_after_complex
    ensure_complex

    tc = TooComplex.new
    tc.send("a#{RubyVM::Shape::SHAPE_MAX_VARIATIONS}_m")
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
    assert_equal nil, tc.iv_not_defined
    assert_predicate RubyVM::Shape.of(tc), :too_complex?
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
    assert_equal 0, initial_shape.next_field_index

    example.add_foo # makes a transition
    add_foo_shape = RubyVM::Shape.of(example)
    assert_equal([:@foo], example.instance_variables)
    assert_equal(initial_shape.id, add_foo_shape.parent.id)
    assert_equal(1, add_foo_shape.next_field_index)

    example.remove_foo # makes a transition
    remove_foo_shape = RubyVM::Shape.of(example)
    assert_equal([], example.instance_variables)
    assert_shape_equal(initial_shape, remove_foo_shape)

    example.add_bar # makes a transition
    bar_shape = RubyVM::Shape.of(example)
    assert_equal([:@bar], example.instance_variables)
    assert_equal(initial_shape.id, bar_shape.parent_id)
    assert_equal(1, bar_shape.next_field_index)
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
    obj = TestObject.new
    shape = RubyVM::Shape.of(obj)
    assert_equal RubyVM::Shape::SHAPE_T_OBJECT, shape.type
    assert_nil shape.parent
  end

  def test_str_has_root_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of(""))
  end

  def test_array_has_root_shape
    assert_shape_equal(RubyVM::Shape.root_shape, RubyVM::Shape.of([]))
  end

  def test_true_has_special_const_shape_id
    assert_equal(RubyVM::Shape::SPECIAL_CONST_SHAPE_ID, RubyVM::Shape.of(true).id)
  end

  def test_nil_has_special_const_shape_id
    assert_equal(RubyVM::Shape::SPECIAL_CONST_SHAPE_ID, RubyVM::Shape.of(nil).id)
  end

  def test_root_shape_transition_to_special_const_on_frozen
    assert_equal(RubyVM::Shape::SPECIAL_CONST_SHAPE_ID, RubyVM::Shape.of([].freeze).id)
  end

  def test_basic_shape_transition
    obj = Example.new
    shape = RubyVM::Shape.of(obj)
    refute_equal(RubyVM::Shape.root_shape, shape)
    assert_equal :@a, shape.edge_name
    assert_equal RubyVM::Shape::SHAPE_IVAR, shape.type

    shape = shape.parent
    assert_equal RubyVM::Shape::SHAPE_T_OBJECT, shape.type
    assert_nil shape.parent

    assert_equal(1, obj.instance_variable_get(:@a))
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

  def test_duplicating_too_complex_objects_memory_leak
    assert_no_memory_leak([], "#{<<~'begin;'}", "#{<<~'end;'}", "[Bug #20162]", rss: true)
      RubyVM::Shape.exhaust_shapes

      o = Object.new
      o.instance_variable_set(:@a, 0)
    begin;
      1_000_000.times do
        o.dup
      end
    end;
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

  def test_cloning_with_freeze_option
    obj = Object.new
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    refute_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
    assert_equal(RubyVM::Shape::SHAPE_FROZEN, RubyVM::Shape.of(obj2).type)
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2).parent)
  end

  def test_freezing_and_cloning_object_with_ivars
    obj = Example.new.freeze
    obj2 = obj.clone(freeze: true)
    assert_predicate(obj2, :frozen?)
    assert_shape_equal(RubyVM::Shape.of(obj), RubyVM::Shape.of(obj2))
    assert_equal(obj2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_cloning_string
    str = ("str" + "str").freeze
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
