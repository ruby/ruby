require 'test/unit'
require "securerandom"

class TestObjectId < Test::Unit::TestCase
  def setup
    @obj = Object.new
  end

  def test_dup_new_id
    id = @obj.object_id
    refute_equal id, @obj.dup.object_id
  end

  def test_dup_with_ivar_and_id
    id = @obj.object_id
    @obj.instance_variable_set(:@foo, 42)

    copy = @obj.dup
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_dup_with_id_and_ivar
    @obj.instance_variable_set(:@foo, 42)
    id = @obj.object_id

    copy = @obj.dup
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_dup_with_id_and_ivar_and_frozen
    @obj.instance_variable_set(:@foo, 42)
    @obj.freeze
    id = @obj.object_id

    copy = @obj.dup
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
    refute_predicate copy, :frozen?
  end

  def test_clone_new_id
    id = @obj.object_id
    refute_equal id, @obj.clone.object_id
  end

  def test_clone_with_ivar_and_id
    id = @obj.object_id
    @obj.instance_variable_set(:@foo, 42)

    copy = @obj.clone
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_clone_with_id_and_ivar
    @obj.instance_variable_set(:@foo, 42)
    id = @obj.object_id

    copy = @obj.clone
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_clone_with_id_and_ivar_and_frozen
    @obj.instance_variable_set(:@foo, 42)
    @obj.freeze
    id = @obj.object_id

    copy = @obj.clone
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
    assert_predicate copy, :frozen?
  end

  def test_marshal_new_id
    return pass if @obj.is_a?(Module)

    id = @obj.object_id
    refute_equal id, Marshal.load(Marshal.dump(@obj)).object_id
  end

  def test_marshal_with_ivar_and_id
    return pass if @obj.is_a?(Module)

    id = @obj.object_id
    @obj.instance_variable_set(:@foo, 42)

    copy = Marshal.load(Marshal.dump(@obj))
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_marshal_with_id_and_ivar
    return pass if @obj.is_a?(Module)

    @obj.instance_variable_set(:@foo, 42)
    id = @obj.object_id

    copy = Marshal.load(Marshal.dump(@obj))
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
  end

  def test_marshal_with_id_and_ivar_and_frozen
    return pass if @obj.is_a?(Module)

    @obj.instance_variable_set(:@foo, 42)
    @obj.freeze
    id = @obj.object_id

    copy = Marshal.load(Marshal.dump(@obj))
    refute_equal id, copy.object_id
    assert_equal 42, copy.instance_variable_get(:@foo)
    refute_predicate copy, :frozen?
  end
end

class TestObjectIdClass < TestObjectId
  def setup
    @obj = Class.new
  end
end

class TestObjectIdGeneric < TestObjectId
  def setup
    @obj = Array.new
  end
end

class TestObjectIdTooComplex < TestObjectId
  class TooComplex
    def initialize
      @too_complex_obj_id_test = 1
    end
  end

  def setup
    if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS)
      assert_equal 8, RubyVM::Shape::SHAPE_MAX_VARIATIONS
    end
    8.times do |i|
      TooComplex.new.instance_variable_set("@TestObjectIdTooComplex#{i}", 1)
    end
    @obj = TooComplex.new
    @obj.instance_variable_set("@a#{rand(10_000)}", 1)

    if defined?(RubyVM::Shape)
      assert_predicate(RubyVM::Shape.of(@obj), :too_complex?)
    end
  end
end

class TestObjectIdTooComplexClass < TestObjectId
  class TooComplex < Module
  end

  def setup
    if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS)
      assert_equal 8, RubyVM::Shape::SHAPE_MAX_VARIATIONS
    end

    @obj = TooComplex.new

    @obj.instance_variable_set("@___#{SecureRandom.hex}", 1)

    8.times do |i|
      @obj.instance_variable_set("@TestObjectIdTooComplexClass#{i}", 1)
      @obj.remove_instance_variable("@TestObjectIdTooComplexClass#{i}")
    end

    @obj.instance_variable_set("@test", 1)

    if defined?(RubyVM::Shape)
      assert_predicate(RubyVM::Shape.of(@obj), :too_complex?)
    end
  end
end

class TestObjectIdTooComplexGeneric < TestObjectId
  class TooComplex < Array
  end

  def setup
    if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS)
      assert_equal 8, RubyVM::Shape::SHAPE_MAX_VARIATIONS
    end
    8.times do |i|
      TooComplex.new.instance_variable_set("@TestObjectIdTooComplexGeneric#{i}", 1)
    end
    @obj = TooComplex.new
    @obj.instance_variable_set("@a#{rand(10_000)}", 1)
    @obj.instance_variable_set("@a#{rand(10_000)}", 1)

    if defined?(RubyVM::Shape)
      assert_predicate(RubyVM::Shape.of(@obj), :too_complex?)
    end
  end
end

class TestObjectIdRactor < Test::Unit::TestCase
  def test_object_id_race_free
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false
      class MyClass
        attr_reader :a, :b, :c
        def initialize
          @a = @b = @c = nil
        end
      end
      N = 10_000
      objs = Ractor.make_shareable(N.times.map { MyClass.new })
      results = 4.times.map{
        Ractor.new(objs) { |objs|
          vars = []
          ids = []
          objs.each do |obj|
            vars << obj.a << obj.b << obj.c
            ids << obj.object_id
          end
          [vars, ids]
        }
      }.map(&:value)
      assert_equal 1, results.uniq.size
    end;
  end

  def test_object_id_race_free_with_stress_compact
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false
      class MyClass
        attr_reader :a, :b, :c
        def initialize
          @a = @b = @c = nil
        end
      end
      N = 50
      objs = Ractor.make_shareable(N.times.map { MyClass.new })

      GC.stress = true
      GC.auto_compact = true if GC.respond_to?(:auto_compact=)

      results = 4.times.map{
        Ractor.new(objs) { |objs|
          vars = []
          ids = []
          objs.each do |obj|
            vars << obj.a << obj.b << obj.c
            ids << obj.object_id
          end
          [vars, ids]
        }
      }.map(&:value)
      assert_equal 1, results.uniq.size
    end;
  end
end
