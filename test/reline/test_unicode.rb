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

  def test_take_range
    assert_equal 'cdef', Reline::Unicode.take_range('abcdefghi', 2, 4)
    assert_equal 'いう', Reline::Unicode.take_range('あいうえお', 2, 4)
  end
end
