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

  def test_caller_bactrace_location
    begin
      line = __LINE__; assert_fail_for_backtrace_location
    rescue Test::Unit::AssertionFailedError => e
    end
    location = Test::Unit::Runner.new.location(e)
    assert_equal "#{__FILE__}:#{line}", location
  end

  def assert_fail_for_backtrace_location
    assert false
  end

  VersionClass = Struct.new(:version) do
    def version?(*ver)
      Test::Unit::CoreAssertions.version_match?(ver, self.version)
    end
  end

  V14_6_0 = VersionClass.new([14, 6, 0])
  V15_0_0 = VersionClass.new([15, 0, 0])

  def test_version_match_integer
    assert_not_operator(V14_6_0, :version?, 13)
    assert_operator(V14_6_0, :version?, 14)
    assert_not_operator(V14_6_0, :version?, 15)
    assert_not_operator(V15_0_0, :version?, 14)
    assert_operator(V15_0_0, :version?, 15)
  end

  def test_version_match_integer_range
    assert_operator(V14_6_0, :version?, 13..14)
    assert_not_operator(V15_0_0, :version?, 13..14)
    assert_not_operator(V14_6_0, :version?, 13...14)
    assert_not_operator(V15_0_0, :version?, 13...14)
  end

  def test_version_match_array_range
    assert_operator(V14_6_0, :version?, [14, 0]..[14, 6])
    assert_not_operator(V15_0_0, :version?, [14, 0]..[14, 6])
    assert_not_operator(V14_6_0, :version?, [14, 0]...[14, 6])
    assert_not_operator(V15_0_0, :version?, [14, 0]...[14, 6])
    assert_operator(V14_6_0, :version?, [14, 0]..[15])
    assert_operator(V15_0_0, :version?, [14, 0]..[15])
    assert_operator(V14_6_0, :version?, [14, 0]...[15])
    assert_not_operator(V15_0_0, :version?, [14, 0]...[15])
  end

  def test_version_match_integer_endless_range
    assert_operator(V14_6_0, :version?, 14..)
    assert_operator(V15_0_0, :version?, 14..)
    assert_not_operator(V14_6_0, :version?, 15..)
    assert_operator(V15_0_0, :version?, 15..)
  end

  def test_version_match_integer_endless_range_exclusive
    assert_operator(V14_6_0, :version?, 14...)
    assert_operator(V15_0_0, :version?, 14...)
    assert_not_operator(V14_6_0, :version?, 15...)
    assert_operator(V15_0_0, :version?, 15...)
  end

  def test_version_match_array_endless_range
    assert_operator(V14_6_0, :version?, [14, 5]..)
    assert_operator(V15_0_0, :version?, [14, 5]..)
    assert_not_operator(V14_6_0, :version?, [14, 7]..)
    assert_operator(V15_0_0, :version?, [14, 7]..)
    assert_not_operator(V14_6_0, :version?, [15]..)
    assert_operator(V15_0_0, :version?, [15]..)
    assert_not_operator(V14_6_0, :version?, [15, 0]..)
    assert_operator(V15_0_0, :version?, [15, 0]..)
  end

  def test_version_match_array_endless_range_exclude_end
    assert_operator(V14_6_0, :version?, [14, 5]...)
    assert_operator(V15_0_0, :version?, [14, 5]...)
    assert_not_operator(V14_6_0, :version?, [14, 7]...)
    assert_operator(V15_0_0, :version?, [14, 7]...)
    assert_not_operator(V14_6_0, :version?, [15]...)
    assert_operator(V15_0_0, :version?, [15]...)
    assert_not_operator(V14_6_0, :version?, [15, 0]...)
    assert_operator(V15_0_0, :version?, [15, 0]...)
  end

  def test_version_match_integer_beginless_range
    assert_operator(V14_6_0, :version?, ..14)
    assert_not_operator(V15_0_0, :version?, ..14)
    assert_operator(V14_6_0, :version?, ..15)
    assert_operator(V15_0_0, :version?, ..15)

    assert_not_operator(V14_6_0, :version?, ...14)
    assert_not_operator(V15_0_0, :version?, ...14)
    assert_operator(V14_6_0, :version?, ...15)
    assert_not_operator(V15_0_0, :version?, ...15)
  end

  def test_version_match_array_beginless_range
    assert_not_operator(V14_6_0, :version?, ..[14, 5])
    assert_not_operator(V15_0_0, :version?, ..[14, 5])
    assert_operator(V14_6_0, :version?, ..[14, 6])
    assert_not_operator(V15_0_0, :version?, ..[14, 6])
    assert_operator(V14_6_0, :version?, ..[15])
    assert_operator(V15_0_0, :version?, ..[15])
    assert_operator(V14_6_0, :version?, ..[15, 0])
    assert_operator(V15_0_0, :version?, ..[15, 0])
  end

  def test_version_match_array_beginless_range_exclude_end
    assert_not_operator(V14_6_0, :version?, ...[14, 5])
    assert_not_operator(V15_0_0, :version?, ...[14, 5])
    assert_not_operator(V14_6_0, :version?, ...[14, 6])
    assert_not_operator(V15_0_0, :version?, ...[14, 6])
    assert_operator(V14_6_0, :version?, ...[15])
    assert_not_operator(V15_0_0, :version?, ...[15])
    assert_operator(V14_6_0, :version?, ...[15, 0])
    assert_not_operator(V15_0_0, :version?, ...[15, 0])
  end
end
