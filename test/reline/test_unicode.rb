require_relative 'helper'
require "reline/unicode"

class Reline::Unicode::Test < Reline::TestCase
  def setup
    Reline.send(:test_mode)
  end

  def teardown
    Reline.test_reset
  end

  def test_get_mbchar_width
    assert_equal Reline.ambiguous_width, Reline::Unicode.get_mbchar_width('é')
  end

  def test_ambiguous_width
    assert_equal 2, Reline::Unicode.calculate_width('√', true)
  end

  def test_split_by_width
    assert_equal [['abc', nil, 'de'], 2], Reline::Unicode.split_by_width('abcde', 3)
    assert_equal [['abc', nil, 'def', nil, ''], 3], Reline::Unicode.split_by_width('abcdef', 3)
    assert_equal [['ab', nil, 'あd', nil, 'ef'], 3], Reline::Unicode.split_by_width('abあdef', 3)
    assert_equal [["ab\1zero\2c", nil, 'def', nil, ''], 3], Reline::Unicode.split_by_width("ab\1zero\2cdef", 3)
    assert_equal [["\e[31mabc", nil, "\e[31md\e[42mef", nil, "\e[31m\e[42mg"], 3], Reline::Unicode.split_by_width("\e[31mabcd\e[42mefg", 3)
    assert_equal [["ab\e]0;1\ac", nil, "\e]0;1\ad"], 2], Reline::Unicode.split_by_width("ab\e]0;1\acd", 3)
  end

  def test_take_range
    assert_equal 'cdef', Reline::Unicode.take_range('abcdefghi', 2, 4)
    assert_equal 'いう', Reline::Unicode.take_range('あいうえお', 2, 4)
  end
end
