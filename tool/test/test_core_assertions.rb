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
