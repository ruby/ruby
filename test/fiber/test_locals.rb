# frozen_string_literal: true
require 'test/unit'

class TestFiberLocals < Test::Unit::TestCase
  def test_locals
    assert_kind_of Hash, Fiber.current.locals
    assert_predicate Fiber.current.locals, :empty?
  end

  def test_locals_inherited
    locals = Fiber.current.locals

    Fiber.new do
      assert_equal locals, Fiber.current.locals
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

  def test_enumerator
    Fiber.current.locals = {item: "Hello World"}
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
end
