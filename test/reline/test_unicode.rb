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
    assert_equal 1, Reline::Unicode.calculate_width('√', true)
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
    assert_equal [['ab[zero]c', nil, 'def', nil, ''], 3], Reline::Unicode.split_by_width("ab\1[zero]\2cdef", 3)
    assert_equal [["\e[31mabc", nil, "\e[31md\e[42mef", nil, "\e[31m\e[42mg"], 3], Reline::Unicode.split_by_width("\e[31mabcd\e[42mefg", 3)
    assert_equal [["ab\e]0;1\ac", nil, "\e]0;1\ad"], 2], Reline::Unicode.split_by_width("ab\e]0;1\acd", 3)
  end

  def test_split_by_width_csi_reset_sgr_optimization
    assert_equal [["\e[1ma\e[mb\e[2mc", nil, "\e[2md\e[0me\e[3mf", nil, "\e[3mg"], 3], Reline::Unicode.split_by_width("\e[1ma\e[mb\e[2mcd\e[0me\e[3mfg", 3)
    assert_equal [["\e[1ma\e[mzero\e[0m\e[2mb", nil, "\e[1m\e[2mc"], 2], Reline::Unicode.split_by_width("\e[1ma\1\e[mzero\e[0m\2\e[2mbc", 2)
  end

  def test_take_range
    assert_equal 'cdef', Reline::Unicode.take_range('abcdefghi', 2, 4)
    assert_equal 'あde', Reline::Unicode.take_range('abあdef', 2, 4)
    assert_equal '[zero]cdef', Reline::Unicode.take_range("ab\1[zero]\2cdef", 2, 4)
    assert_equal 'b[zero]cde', Reline::Unicode.take_range("ab\1[zero]\2cdef", 1, 4)
    assert_equal "\e[31mcd\e[42mef", Reline::Unicode.take_range("\e[31mabcd\e[42mefg", 2, 4)
    assert_equal "\e]0;1\acd", Reline::Unicode.take_range("ab\e]0;1\acd", 2, 3)
    assert_equal 'いう', Reline::Unicode.take_range('あいうえお', 2, 4)
  end

  def test_nonprinting_start_end
    # \1 and \2 should be removed
    assert_equal 'ab[zero]cd', Reline::Unicode.take_range("ab\1[zero]\2cdef", 0, 4)
    assert_equal [['ab[zero]cd', nil, 'ef'], 2], Reline::Unicode.split_by_width("ab\1[zero]\2cdef", 4)
    # CSI between \1 and \2 does not need to be applied to the sebsequent line
    assert_equal [["\e[31mab\e[32mcd", nil, "\e[31mef"], 2], Reline::Unicode.split_by_width("\e[31mab\1\e[32m\2cdef", 4)
  end

  def test_strip_non_printing_start_end
    assert_equal "ab[zero]cd[ze\1ro]ef[zero]", Reline::Unicode.strip_non_printing_start_end("ab\1[zero]\2cd\1[ze\1ro]\2ef\1[zero]")
  end

  def test_calculate_width
    assert_equal 9, Reline::Unicode.calculate_width('abcdefghi')
    assert_equal 9, Reline::Unicode.calculate_width('abcdefghi', true)
    assert_equal 7, Reline::Unicode.calculate_width('abあdef')
    assert_equal 7, Reline::Unicode.calculate_width('abあdef', true)
    assert_equal 16, Reline::Unicode.calculate_width("ab\1[zero]\2cdef")
    assert_equal 6, Reline::Unicode.calculate_width("ab\1[zero]\2cdef", true)
    assert_equal 19, Reline::Unicode.calculate_width("\e[31mabcd\e[42mefg")
    assert_equal 7, Reline::Unicode.calculate_width("\e[31mabcd\e[42mefg", true)
    assert_equal 12, Reline::Unicode.calculate_width("ab\e]0;1\acd")
    assert_equal 4, Reline::Unicode.calculate_width("ab\e]0;1\acd", true)
    assert_equal 10, Reline::Unicode.calculate_width('あいうえお')
    assert_equal 10, Reline::Unicode.calculate_width('あいうえお', true)
  end

  def test_take_mbchar_range
    assert_equal ['cdef', 2, 4], Reline::Unicode.take_mbchar_range('abcdefghi', 2, 4)
    assert_equal ['cdef', 2, 4], Reline::Unicode.take_mbchar_range('abcdefghi', 2, 4, padding: true)
    assert_equal ['cdef', 2, 4], Reline::Unicode.take_mbchar_range('abcdefghi', 2, 4, cover_begin: true)
    assert_equal ['cdef', 2, 4], Reline::Unicode.take_mbchar_range('abcdefghi', 2, 4, cover_end: true)
    assert_equal ['いう', 2, 4], Reline::Unicode.take_mbchar_range('あいうえお', 2, 4)
    assert_equal ['いう', 2, 4], Reline::Unicode.take_mbchar_range('あいうえお', 2, 4, padding: true)
    assert_equal ['いう', 2, 4], Reline::Unicode.take_mbchar_range('あいうえお', 2, 4, cover_begin: true)
    assert_equal ['いう', 2, 4], Reline::Unicode.take_mbchar_range('あいうえお', 2, 4, cover_end: true)
    assert_equal ['う', 4, 2], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4)
    assert_equal [' う ', 3, 4], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4, padding: true)
    assert_equal ['いう', 2, 4], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4, cover_begin: true)
    assert_equal ['うえ', 4, 4], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4, cover_end: true)
    assert_equal ['いう ', 2, 5], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4, cover_begin: true, padding: true)
    assert_equal [' うえ', 3, 5], Reline::Unicode.take_mbchar_range('あいうえお', 3, 4, cover_end: true, padding: true)
    assert_equal [' うえお   ', 3, 10], Reline::Unicode.take_mbchar_range('あいうえお', 3, 10, padding: true)
    assert_equal [" \e[41mうえお\e[0m   ", 3, 10], Reline::Unicode.take_mbchar_range("あい\e[41mうえお", 3, 10, padding: true)
    assert_equal ["\e[41m \e[42mい\e[43m ", 1, 4], Reline::Unicode.take_mbchar_range("\e[41mあ\e[42mい\e[43mう", 1, 4, padding: true)
    assert_equal ["\e[31mc[ABC]d\e[0mef", 2, 4], Reline::Unicode.take_mbchar_range("\e[31mabc\1[ABC]\2d\e[0mefghi", 2, 4)
    assert_equal ["\e[41m \e[42mい\e[43m ", 1, 4], Reline::Unicode.take_mbchar_range("\e[41mあ\e[42mい\e[43mう", 1, 4, padding: true)
  end

  def test_encoding_conversion
    texts = [
      String.new("invalid\xFFutf8", encoding: 'utf-8'),
      String.new("invalid\xFFsjis", encoding: 'sjis'),
      "utf8#{33111.chr('sjis')}convertible",
      "utf8#{33222.chr('sjis')}inconvertible",
      "sjis->utf8->sjis#{60777.chr('sjis')}irreversible"
    ]
    utf8_texts = [
      'invalid�utf8',
      'invalid�sjis',
      'utf8仝convertible',
      'utf8�inconvertible',
      'sjis->utf8->sjis劦irreversible'
    ]
    sjis_texts = [
      'invalid?utf8',
      'invalid?sjis',
      "utf8#{33111.chr('sjis')}convertible",
      'utf8?inconvertible',
      "sjis->utf8->sjis#{60777.chr('sjis')}irreversible"
    ]
    assert_equal(utf8_texts, texts.map { |s| Reline::Unicode.safe_encode(s, 'utf-8') })
    assert_equal(utf8_texts, texts.map { |s| Reline::Unicode.safe_encode(s, Encoding::UTF_8) })
    assert_equal(sjis_texts, texts.map { |s| Reline::Unicode.safe_encode(s, 'sjis') })
    assert_equal(sjis_texts, texts.map { |s| Reline::Unicode.safe_encode(s, Encoding::Windows_31J) })
  end
end
