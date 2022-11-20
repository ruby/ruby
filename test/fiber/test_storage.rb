# frozen_string_literal: true
require 'test/unit'

class TestFiberStorage < Test::Unit::TestCase
  def test_storage
    Fiber.new do
      Fiber[:x] = 10
      assert_kind_of Hash, Fiber.current.storage
      assert_predicate Fiber.current.storage, :any?
    end.resume
  end

  def test_storage_inherited
    Fiber.new do
      Fiber[:foo] = :bar

      Fiber.new do
        assert_equal :bar, Fiber[:foo]
        Fiber[:bar] = :baz
      end.resume

      assert_nil Fiber[:bar]
    end.resume
  end

  def test_variable_assignment
    Fiber.new do
      Fiber[:foo] = :bar
      assert_equal :bar, Fiber[:foo]
    end.resume
  end

  def test_storage_assignment
    Fiber.new do
      Fiber.current.storage = {foo: :bar}
      assert_equal :bar, Fiber[:foo]
    end.resume
  end

  def test_inherited_storage
    Fiber.new do
      Fiber.current.storage = {foo: :bar}
      f = Fiber.new do
        assert_equal :bar, Fiber[:foo]
      end
      f.resume
    end.resume
  end

  def test_enumerator_inherited_storage
    Fiber.new do
      Fiber[:item] = "Hello World"

      enumerator = Enumerator.new do |out|
        out << Fiber.current
        out << Fiber[:item]
      end

      # The fiber within the enumerator is not equal to the current...
      assert_not_equal Fiber.current, enumerator.next

      # But it inherited the storage from the current fiber:
      assert_equal "Hello World", enumerator.next
    end.resume
  end

  def test_thread_inherited_storage
    Fiber.new do
      Fiber[:x] = 10

      x = Thread.new do
        Fiber[:y] = 20
        Fiber[:x]
      end.value

      assert_equal 10, x
      assert_equal nil, Fiber[:y]
    end.resume
  end

  def test_enumerator_count
    Fiber.new do
      Fiber[:count] = 0

      enumerator = Enumerator.new do |y|
        # Since the fiber is implementation detail, the storage are shared with the parent:
        Fiber[:count] += 1
        y << Fiber[:count]
      end

      assert_equal 1, enumerator.next
      assert_equal 1, Fiber[:count]
    end.resume
  end

  def test_storage_assignment_type_error
    assert_raise(TypeError) do
      Fiber.new(storage: {"foo" => "bar"}) {}
    end
  end
end
