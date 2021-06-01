# frozen_string_literal: true
require 'test/unit'
require 'fiber'

class TestFiberBacktrace < Test::Unit::TestCase
  def test_backtrace
    backtrace = Fiber.current.backtrace
    assert_kind_of Array, backtrace
    assert_match(/test_backtrace/, backtrace[0])
  end

  def test_backtrace_locations
    backtrace = Fiber.current.backtrace_locations
    assert_kind_of Array, backtrace
    assert_match(/test_backtrace_locations/, backtrace[1].label)
  end

  def test_local_backtrace
    backtrace = Fiber.current.backtrace(2)
    assert_equal backtrace, caller
  end
end
