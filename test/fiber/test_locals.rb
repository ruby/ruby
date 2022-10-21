# frozen_string_literal: true
require 'test/unit'

class TestFiberLocals < Test::Unit::TestCase
  def test_locals
    Fiber[:x] = 10
    assert_kind_of Hash, Fiber.current.locals
    assert_predicate Fiber.current.locals, :any?
  end

  def test_locals_inherited
    locals = Fiber.current.locals
    locals[:foo] = :bar

    Fiber.new do
      assert_equal locals, Fiber.current.locals
      Fiber[:bar] = :baz
      assert_not_equal locals, Fiber.current.locals
    end.resume
  end

  def test_variable_assignment
    Fiber[:foo] = :bar
    assert_equal :bar, Fiber[:foo]
  ensure
    Fiber.current.locals.clear
  end

  def test_locals_assignment
    Fiber.current.locals = {foo: :bar}
    assert_equal :bar, Fiber[:foo]
  ensure
    Fiber.current.locals.clear
  end

  def test_inherited_locals
    Fiber.current.locals = {foo: :bar}
    f = Fiber.new do
      assert_equal :bar, Fiber[:foo]
    end
    f.resume
  ensure
    Fiber.current.locals.clear
  end

  def test_enumerator_inherited_locals
    Fiber[:item] = "Hello World"

    enumerator = Enumerator.new do |out|
      out << Fiber.current
      out << Fiber[:item]
    end

    # The fiber within the enumerator is not equal to the current...
    assert_not_equal Fiber.current, enumerator.next

    # But it inherited the locals from the current fiber:
    assert_equal "Hello World", enumerator.next
  ensure
    Fiber.current.locals.clear
  end

  def test_thread_inherited_locals
    Fiber[:x] = 10

    x = Thread.new do
      Fiber[:y] = 20
      Fiber[:x]
    end.value

    assert_equal 10, x
    assert_equal nil, Fiber[:y]
  ensure
    Fiber.current.locals.clear
  end

  def test_enumerator_count
    Fiber[:count] = 0

    enumerator = Enumerator.new do |y|
      # Since the fiber is implementation detail, the locals are shared with the parent:
      Fiber[:count] += 1
      y << Fiber[:count]
    end

    assert_equal 1, enumerator.next
    assert_equal 1, Fiber[:count]
  ensure
    Fiber.current.locals.clear
  end
end
