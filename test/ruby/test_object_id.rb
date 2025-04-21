require 'test/unit'

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
  end

  def setup
    if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS)
      assert_equal 8, RubyVM::Shape::SHAPE_MAX_VARIATIONS
    end
    8.times do |i|
      TooComplex.new.instance_variable_set("@a#{i}", 1)
    end
    @obj = TooComplex.new
    @obj.instance_variable_set(:@test, 1)
  end
end

class TestObjectIdTooComplexClass < TestObjectId
  class TooComplex < Module
  end

  def setup
    if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS)
      assert_equal 8, RubyVM::Shape::SHAPE_MAX_VARIATIONS
    end
    8.times do |i|
      TooComplex.new.instance_variable_set("@a#{i}", 1)
    end
    @obj = TooComplex.new
    @obj.instance_variable_set(:@test, 1)
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
      TooComplex.new.instance_variable_set("@a#{i}", 1)
    end
    @obj = TooComplex.new
    @obj.instance_variable_set(:@test, 1)
  end
end
