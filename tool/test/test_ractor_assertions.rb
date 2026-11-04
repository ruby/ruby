# frozen_string_literal: true

require "test/unit"

class TestRactorAssertions < Test::Unit::TestCase
  include Test::Unit::CoreAssertions

  def test_assert_in_ractor_return_value
    assert_separately([], <<~RUBY)
      assert_in_ractor(1, [2, 3]) do |one, ary|
        "the result"
      end => result

      assert_equal("the result", result)
    RUBY
  end

  def test_assert_in_ractor_counts_assertions
    assert_separately([], <<~RUBY)
      before = _assertions
      assert_in_ractor do
        assert true
        assert true
      end

      assert_equal(2, _assertions - before)
    RUBY
  end

  def test_assert_in_ractor_failure
    assert_separately([], <<~RUBY)
      error = assert_raise(Test::Unit::AssertionFailedError) do
        assert_in_ractor { assert_equal(1, 2) }
      end

      assert_match(/<1> expected but was/, error.message)
      assert_include(error.backtrace.join("\n"), __FILE__)
    RUBY
  end

  def test_assert_in_ractor_error
    assert_separately([], <<~RUBY)
      error = assert_raise(RuntimeError) do
        assert_in_ractor { raise "boom" }
      end

      assert_equal("boom", error.message)
      assert_include(error.backtrace.join("\n"), __FILE__)
    RUBY
  end
end
