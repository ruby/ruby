# frozen_string_literal: true

require "test/unit"
require "core_assertions"

class TestCoreAssertions < Test::Unit::TestCase
  include Test::Unit::CoreAssertions

  def test_backtrace_filter_handles_missing_backtrace
    assert_equal(["No backtrace"], Test.filter_backtrace(nil))
  end

  def test_backtrace_filter_removes_internal_entries
    backtrace = [
      "/tmp/example.rb:1:in `run'",
      "/tmp/lib/test/unit.rb:2:in `assert'",
    ]

    assert_equal([backtrace.first], Test.filter_backtrace(backtrace))
  end

  def test_message_adds_sentence_endings
    object = Object.new
    object.extend(Test::Unit::Assertions)

    message = object.message("details") { "default" }

    assert_equal("details.\ndefault.", message.call)
  end

  def test_memory_growth_is_not_settled_by_a_small_slope_decrease
    samples = [
      19_759_104, 40_828_928, 49_414_144, 59_277_312, 68_714_496,
      77_955_072, 87_113_728, 96_468_992, 105_005_056, 113_754_112,
      122_568_704,
    ]

    early_rate, late_rate = send(:memory_growth_rates, samples)

    assert_not_send([self, :memory_growth_settled?, early_rate, late_rate, 0.25])
    assert_send([self, :memory_growth_settled?, early_rate, late_rate, 0.9])
  end

  def test_memory_growth_is_settled_after_growth_stops
    early_rate, late_rate = send(:memory_growth_rates, [0, 10, 20, 30, 30, 30, 30, 30])

    assert_send([self, :memory_growth_settled?, early_rate, late_rate, 0.25])
  end

  def test_memory_growth_ratio_zero_requires_nonincreasing_usage
    assert_send([self, :memory_growth_settled?, 10.0, 0.0, 0.0])
    assert_not_send([self, :memory_growth_settled?, 10.0, 0.1, 0.0])
  end

  def test_assert_separately_runs_assertions_in_child_ruby
    assert_separately([], <<~RUBY)
      assert_equal(4, 2 + 2)
    RUBY
  end

  def test_assert_separately_propagates_child_failure
    error = assert_raise(Test::Unit::AssertionFailedError) do
      assert_separately([], <<~RUBY)
        assert_equal(:expected, :actual)
      RUBY
    end

    assert_match(/expected/, error.message)
  end
end
