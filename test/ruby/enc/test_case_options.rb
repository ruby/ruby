# Copyright © 2016 Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class TestCaseOptions < Test::Unit::TestCase
  def assert_raise_functional_operations(arg, *options)
    assert_raise(ArgumentError) { arg.upcase(*options) }
    assert_raise(ArgumentError) { arg.downcase(*options) }
    assert_raise(ArgumentError) { arg.capitalize(*options) }
    assert_raise(ArgumentError) { arg.swapcase(*options) }
  end

  def assert_raise_bang_operations(arg, *options)
    assert_raise(ArgumentError) { arg.upcase!(*options) }
    assert_raise(ArgumentError) { arg.downcase!(*options) }
    assert_raise(ArgumentError) { arg.capitalize!(*options) }
    assert_raise(ArgumentError) { arg.swapcase!(*options) }
  end

  def assert_raise_both_types(*options)
    assert_raise_functional_operations 'a', *options
    assert_raise_bang_operations 'a', *options
    assert_raise_functional_operations :a, *options
  end

  def test_option_errors
    assert_raise_both_types :invalid
    assert_raise_both_types :lithuanian, :turkic, :fold
    assert_raise_both_types :fold, :fold
    assert_raise_both_types :ascii, :fold
    assert_raise_both_types :fold, :ascii
    assert_raise_both_types :ascii, :turkic
    assert_raise_both_types :turkic, :ascii
    assert_raise_both_types :ascii, :lithuanian
    assert_raise_both_types :lithuanian, :ascii
  end

  def assert_okay_functional_operations(arg, *options)
    assert_nothing_raised { arg.upcase(*options) }
    assert_nothing_raised { arg.downcase(*options) }
    assert_nothing_raised { arg.capitalize(*options) }
    assert_nothing_raised { arg.swapcase(*options) }
  end

  def assert_okay_bang_operations(arg, *options)
    assert_nothing_raised { arg.upcase!(*options) }
    assert_nothing_raised { arg.downcase!(*options) }
    assert_nothing_raised { arg.capitalize!(*options) }
    assert_nothing_raised { arg.swapcase!(*options) }
  end

  def assert_okay_both_types(*options)
    assert_okay_functional_operations 'a', *options
    assert_okay_bang_operations 'a', *options
    assert_okay_functional_operations :a, *options
  end

  def test_options_okay
    assert_okay_both_types
    assert_okay_both_types :ascii
    assert_okay_both_types :turkic
    assert_okay_both_types :lithuanian
    assert_okay_both_types :turkic, :lithuanian
    assert_okay_both_types :lithuanian, :turkic
  end

  def test_operation_specific   # :fold option only allowed on downcase
    assert_nothing_raised { 'a'.downcase :fold }
    assert_raise(ArgumentError) { 'a'.upcase :fold }
    assert_raise(ArgumentError) { 'a'.capitalize :fold }
    assert_raise(ArgumentError) { 'a'.swapcase :fold }
    assert_nothing_raised { 'a'.downcase! :fold }
    assert_raise(ArgumentError) { 'a'.upcase! :fold }
    assert_raise(ArgumentError) { 'a'.capitalize! :fold }
    assert_raise(ArgumentError) { 'a'.swapcase! :fold }
    assert_nothing_raised { :a.downcase :fold }
    assert_raise(ArgumentError) { :a.upcase :fold }
    assert_raise(ArgumentError) { :a.capitalize :fold }
    assert_raise(ArgumentError) { :a.swapcase :fold }
  end
end
