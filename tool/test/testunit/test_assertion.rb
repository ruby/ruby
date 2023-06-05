# frozen_string_literal: false
require 'test/unit'
class TestAssertion < Test::Unit::TestCase
  def test_wrong_assertion
    error, line = assert_raise(ArgumentError) {assert(true, true)}, __LINE__
    assert_match(/assertion message must be String or Proc, but TrueClass was given/, error.message)
    assert_match(/\A#{Regexp.quote(__FILE__)}:#{line}:/, error.backtrace[0])
  end

  def test_timeout_separately
    assert_raise(Timeout::Error) do
      assert_separately([], <<~"end;", timeout: 0.1)
        sleep
      end;
    end
  end

  def return_in_assert_raise
    assert_raise(RuntimeError) do
      return
    end
  end

  def test_assert_raise
    assert_raise(Test::Unit::AssertionFailedError) do
      return_in_assert_raise
    end
  end

  def test_assert_pattern_list
    assert_pattern_list([/foo?/], "foo")
    assert_not_pattern_list([/foo?/], "afoo")
    assert_not_pattern_list([/foo?/], "foo?")
    assert_pattern_list([:*, /foo?/, :*], "foo")
    assert_pattern_list([:*, /foo?/], "afoo")
    assert_not_pattern_list([:*, /foo?/], "afoo?")
    assert_pattern_list([/foo?/, :*], "foo?")

    assert_not_pattern_list(["foo?"], "foo")
    assert_not_pattern_list(["foo?"], "afoo")
    assert_pattern_list(["foo?"], "foo?")
    assert_not_pattern_list([:*, "foo?", :*], "foo")
    assert_not_pattern_list([:*, "foo?"], "afoo")
    assert_pattern_list([:*, "foo?"], "afoo?")
    assert_pattern_list(["foo?", :*], "foo?")
  end

  def assert_not_pattern_list(pattern_list, actual, message=nil)
    assert_raise(Test::Unit::AssertionFailedError) do
      assert_pattern_list(pattern_list, actual, message)
    end
  end
end
