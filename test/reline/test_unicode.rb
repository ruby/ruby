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

  def test_csi_regexp
    csi_sequences = ["\e[m", "\e[1m", "\e[12;34m", "\e[12;34H"]
    assert_equal(csi_sequences, "text#{csi_sequences.join('text')}text".scan(Reline::Unicode::CSI_REGEXP))
  end

  def test_osc_regexp
    osc_sequences = ["\e]1\a", "\e]0;OSC\a", "\e]1\e\\", "\e]0;OSC\e\\"]
    separator = "text\atext"
    assert_equal(osc_sequences, "#{separator}#{osc_sequences.join(separator)}#{separator}".scan(Reline::Unicode::OSC_REGEXP))
  end

  def test_split_by_width
    assert_equal [['abc', nil, 'de'], 2], Reline::Unicode.split_by_width('abcde', 3)
    assert_equal [['abc', nil, 'def', nil, ''], 3], Reline::Unicode.split_by_width('abcdef', 3)
    assert_equal [['ab', nil, 'あd', nil, 'ef'], 3], Reline::Unicode.split_by_width('abあdef', 3)
    assert_equal [["ab\1zero\2c", nil, 'def', nil, ''], 3], Reline::Unicode.split_by_width("ab\1zero\2cdef", 3)
    assert_equal [["\e[31mabc", nil, "\e[31md\e[42mef", nil, "\e[31m\e[42mg"], 3], Reline::Unicode.split_by_width("\e[31mabcd\e[42mefg", 3)
    assert_equal [["ab\e]0;1\ac", nil, "\e]0;1\ad"], 2], Reline::Unicode.split_by_width("ab\e]0;1\acd", 3)
  end

  def test_split_by_width_csi_reset_sgr_optimization
    assert_equal [["\e[1ma\e[mb\e[2mc", nil, "\e[2md\e[0me\e[3mf", nil, "\e[3mg"], 3], Reline::Unicode.split_by_width("\e[1ma\e[mb\e[2mcd\e[0me\e[3mfg", 3)
    assert_equal [["\e[1ma\1\e[mzero\e[0m\2\e[2mb", nil, "\e[1m\e[2mc"], 2], Reline::Unicode.split_by_width("\e[1ma\1\e[mzero\e[0m\2\e[2mbc", 2)
  end

  def test_take_range
    assert_equal 'cdef', Reline::Unicode.take_range('abcdefghi', 2, 4)
    assert_equal 'あde', Reline::Unicode.take_range('abあdef', 2, 4)
    assert_equal 'zerocdef', Reline::Unicode.take_range("ab\1zero\2cdef", 2, 4)
    assert_equal 'bzerocde', Reline::Unicode.take_range("ab\1zero\2cdef", 1, 4)
    assert_equal "\e[31mcd\e[42mef", Reline::Unicode.take_range("\e[31mabcd\e[42mefg", 2, 4)
    assert_equal "\e]0;1\acd", Reline::Unicode.take_range("ab\e]0;1\acd", 2, 3)
    assert_equal 'いう', Reline::Unicode.take_range('あいうえお', 2, 4)
  end

  def test_calculate_width
    assert_equal 9, Reline::Unicode.calculate_width('abcdefghi')
    assert_equal 9, Reline::Unicode.calculate_width('abcdefghi', true)
    assert_equal 7, Reline::Unicode.calculate_width('abあdef')
    assert_equal 7, Reline::Unicode.calculate_width('abあdef', true)
    assert_equal 14, Reline::Unicode.calculate_width("ab\1zero\2cdef")
    assert_equal 6, Reline::Unicode.calculate_width("ab\1zero\2cdef", true)
    assert_equal 19, Reline::Unicode.calculate_width("\e[31mabcd\e[42mefg")
    assert_equal 7, Reline::Unicode.calculate_width("\e[31mabcd\e[42mefg", true)
    assert_equal 12, Reline::Unicode.calculate_width("ab\e]0;1\acd")
    assert_equal 4, Reline::Unicode.calculate_width("ab\e]0;1\acd", true)
    assert_equal 10, Reline::Unicode.calculate_width('あいうえお')
    assert_equal 10, Reline::Unicode.calculate_width('あいうえお', true)
  end
end
