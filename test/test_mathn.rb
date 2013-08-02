require 'test/unit'
require_relative 'ruby/envutil'

# mathn redefines too much. It must be isolated to child processes.
class TestMathn < Test::Unit::TestCase
  def test_power
    assert_in_out_err ['-r', 'mathn', '-e', 'a=1**2;!a'], "", [], [], '[ruby-core:25740]'
    assert_in_out_err ['-r', 'mathn', '-e', 'a=(1 << 126)**2;!a'], "", [], [], '[ruby-core:25740]'
  end

  def assert_separated_equal(options, expected, actual, message = nil)
    assert_in_out_err([*options, '-e', "p((#{actual})==(#{expected}))"], "", ["true"], [], message)
  end

  def test_floor
    assert_separated_equal(%w[-rmathn], " 2", "( 13/5).floor")
    assert_separated_equal(%w[-rmathn], " 2", "(  5/2).floor")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).floor")
    assert_separated_equal(%w[-rmathn], "-3", "(-12/5).floor")
    assert_separated_equal(%w[-rmathn], "-3", "( -5/2).floor")
    assert_separated_equal(%w[-rmathn], "-3", "(-13/5).floor")

    assert_separated_equal(%w[-rmathn], " 2", "( 13/5).floor(0)")
    assert_separated_equal(%w[-rmathn], " 2", "(  5/2).floor(0)")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).floor(0)")
    assert_separated_equal(%w[-rmathn], "-3", "(-12/5).floor(0)")
    assert_separated_equal(%w[-rmathn], "-3", "( -5/2).floor(0)")
    assert_separated_equal(%w[-rmathn], "-3", "(-13/5).floor(0)")

    assert_separated_equal(%w[-rmathn], "( 13/5)", "( 13/5).floor(2)")
    assert_separated_equal(%w[-rmathn], "(  5/2)", "(  5/2).floor(2)")
    assert_separated_equal(%w[-rmathn], "( 12/5)", "( 12/5).floor(2)")
    assert_separated_equal(%w[-rmathn], "(-12/5)", "(-12/5).floor(2)")
    assert_separated_equal(%w[-rmathn], "( -5/2)", "( -5/2).floor(2)")
    assert_separated_equal(%w[-rmathn], "(-13/5)", "(-13/5).floor(2)")
  end

  def test_ceil
    assert_separated_equal(%w[-rmathn], " 3", "( 13/5).ceil")
    assert_separated_equal(%w[-rmathn], " 3", "(  5/2).ceil")
    assert_separated_equal(%w[-rmathn], " 3", "( 12/5).ceil")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).ceil")
    assert_separated_equal(%w[-rmathn], "-2", "( -5/2).ceil")
    assert_separated_equal(%w[-rmathn], "-2", "(-13/5).ceil")

    assert_separated_equal(%w[-rmathn], " 3", "( 13/5).ceil(0)")
    assert_separated_equal(%w[-rmathn], " 3", "(  5/2).ceil(0)")
    assert_separated_equal(%w[-rmathn], " 3", "( 12/5).ceil(0)")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).ceil(0)")
    assert_separated_equal(%w[-rmathn], "-2", "( -5/2).ceil(0)")
    assert_separated_equal(%w[-rmathn], "-2", "(-13/5).ceil(0)")

    assert_separated_equal(%w[-rmathn], "( 13/5)", "( 13/5).ceil(2)")
    assert_separated_equal(%w[-rmathn], "(  5/2)", "(  5/2).ceil(2)")
    assert_separated_equal(%w[-rmathn], "( 12/5)", "( 12/5).ceil(2)")
    assert_separated_equal(%w[-rmathn], "(-12/5)", "(-12/5).ceil(2)")
    assert_separated_equal(%w[-rmathn], "( -5/2)", "( -5/2).ceil(2)")
    assert_separated_equal(%w[-rmathn], "(-13/5)", "(-13/5).ceil(2)")
  end

  def test_truncate
    assert_separated_equal(%w[-rmathn], " 2", "( 13/5).truncate")
    assert_separated_equal(%w[-rmathn], " 2", "(  5/2).truncate")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).truncate")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).truncate")
    assert_separated_equal(%w[-rmathn], "-2", "( -5/2).truncate")
    assert_separated_equal(%w[-rmathn], "-2", "(-13/5).truncate")

    assert_separated_equal(%w[-rmathn], " 2", "( 13/5).truncate(0)")
    assert_separated_equal(%w[-rmathn], " 2", "(  5/2).truncate(0)")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).truncate(0)")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).truncate(0)")
    assert_separated_equal(%w[-rmathn], "-2", "( -5/2).truncate(0)")
    assert_separated_equal(%w[-rmathn], "-2", "(-13/5).truncate(0)")

    assert_separated_equal(%w[-rmathn], "( 13/5)", "( 13/5).truncate(2)")
    assert_separated_equal(%w[-rmathn], "(  5/2)", "(  5/2).truncate(2)")
    assert_separated_equal(%w[-rmathn], "( 12/5)", "( 12/5).truncate(2)")
    assert_separated_equal(%w[-rmathn], "(-12/5)", "(-12/5).truncate(2)")
    assert_separated_equal(%w[-rmathn], "( -5/2)", "( -5/2).truncate(2)")
    assert_separated_equal(%w[-rmathn], "(-13/5)", "(-13/5).truncate(2)")
  end

  def test_round
    assert_separated_equal(%w[-rmathn], " 3", "( 13/5).round")
    assert_separated_equal(%w[-rmathn], " 3", "(  5/2).round")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).round")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).round")
    assert_separated_equal(%w[-rmathn], "-3", "( -5/2).round")
    assert_separated_equal(%w[-rmathn], "-3", "(-13/5).round")

    assert_separated_equal(%w[-rmathn], " 3", "( 13/5).round(0)")
    assert_separated_equal(%w[-rmathn], " 3", "(  5/2).round(0)")
    assert_separated_equal(%w[-rmathn], " 2", "( 12/5).round(0)")
    assert_separated_equal(%w[-rmathn], "-2", "(-12/5).round(0)")
    assert_separated_equal(%w[-rmathn], "-3", "( -5/2).round(0)")
    assert_separated_equal(%w[-rmathn], "-3", "(-13/5).round(0)")

    assert_separated_equal(%w[-rmathn], "( 13/5)", "( 13/5).round(2)")
    assert_separated_equal(%w[-rmathn], "(  5/2)", "(  5/2).round(2)")
    assert_separated_equal(%w[-rmathn], "( 12/5)", "( 12/5).round(2)")
    assert_separated_equal(%w[-rmathn], "(-12/5)", "(-12/5).round(2)")
    assert_separated_equal(%w[-rmathn], "( -5/2)", "( -5/2).round(2)")
    assert_separated_equal(%w[-rmathn], "(-13/5)", "(-13/5).round(2)")
  end
end
