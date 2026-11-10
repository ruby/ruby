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

  def test_memory_growth_tail_is_settled_after_a_late_step
    samples = [0, 10, 20, 30, 30, 30, 30, 30, 40, 50, 60, 60, 60, 60, 60]

    assert_send([self, :memory_growth_settled_in_tail?, samples, 0.25])
  end

  def test_memory_growth_ratio_zero_requires_nonincreasing_usage
    assert_send([self, :memory_growth_settled?, 10.0, 0.0, 0.0])
    assert_not_send([self, :memory_growth_settled?, 10.0, 0.1, 0.0])
  end

  def test_assert_no_memory_leak_stops_at_minimum_sample_count_when_settled
    prepare = <<~'RUBY'
      $memory_sample_count = 0
      END {raise "unexpected sample count" unless $memory_sample_count == 2}
      class FakeMemoryStatus
        attr_reader :size
        def initialize(size) @size = size end
        def to_s; "{#{Memory::Status.members.map {|member| "#{member}:#{size}"}.join(',')}}" end
      end
      Memory::Status.define_singleton_method(:new) {FakeMemoryStatus.new(1)}
    RUBY
    code = '$memory_sample_count += 1; raise "unexpected stdin" unless STDIN.gets.nil?'

    assert_no_memory_leak([], prepare, code, samples: 2..5, growth_rate_ratio: 1.0)
  end

  def test_assert_no_memory_leak_fails_at_maximum_sample_count_when_growth_continues
    prepare = <<~'RUBY'
      $memory_sample_count = 0
      $memory_status_count = 0
      END {raise "unexpected sample count" unless $memory_sample_count == 4}
      class FakeMemoryStatus
        attr_reader :size
        def initialize(size) @size = size end
        def to_s; "{#{Memory::Status.members.map {|member| "#{member}:#{size}"}.join(',')}}" end
      end
      Memory::Status.define_singleton_method(:new) do
        size = 100 + $memory_status_count * 10
        $memory_status_count += 1
        FakeMemoryStatus.new(size)
      end
    RUBY
    code = '$memory_sample_count += 1'

    error = assert_raise(Test::Unit::AssertionFailedError) do
      assert_no_memory_leak([], prepare, code, samples: 2..4, growth_rate_ratio: 0.25)
    end
    assert_match(/growth did not settle/, error.message)
  end

  def test_assert_no_memory_leak_rejects_ranges_without_enough_samples
    error = assert_raise(ArgumentError) do
      assert_no_memory_leak([], "", "", samples: 1..5)
    end
    assert_match(/minimum of 2/, error.message)
  end

  def test_assert_no_memory_leak_applies_timeout_to_sample_range
    assert_raise(Timeout::Error) do
      assert_no_memory_leak([], "", "sleep", samples: 2..5, timeout: 0.1)
    end
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
