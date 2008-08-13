require 'test/unit'

class TestEncodingConverter < Test::Unit::TestCase
  def assert_econv(ret_expected, dst_expected, src_expected, to, from, src, opt={})
    opt[:obuf_len] ||= 100
    src = src.dup
    ec = Encoding::Converter.new(from, to, 0)
    dst = ''
    while true
      ret = ec.primitive_convert(src, dst2="", opt[:obuf_len], 0)
      dst << dst2
      #p [ret, dst, src]
      break if ret != :obuf_full
    end
    assert_equal([ret_expected, dst_expected, src_expected], [ret, dst, src])
  end

  def test_eucjp_to_utf8
    assert_econv(:finished, "", "", "EUC-JP", "UTF-8", "")
    assert_econv(:finished, "a", "", "EUC-JP", "UTF-8", "a")
  end

  def test_iso2022jp
    assert_econv(:finished, "", "", "ISO-2022-JP", "Shift_JIS", "")
  end

  def test_invalid
    assert_econv(:invalid_input, "", "", "EUC-JP", "UTF-8", "\x80")
    assert_econv(:invalid_input, "a", "", "EUC-JP", "UTF-8", "a\x80")
    assert_econv(:invalid_input, "a", "\x80", "EUC-JP", "UTF-8", "a\x80\x80")
    assert_econv(:invalid_input, "abc", "def", "EUC-JP", "UTF-8", "abc\xFFdef")
    assert_econv(:invalid_input, "abc", "def", "EUC-JP", "Shift_JIS", "abc\xFFdef")
    assert_econv(:invalid_input, "abc", "def", "EUC-JP", "Shift_JIS", "abc\xFFdef", :obuf_len=>1)
    assert_econv(:invalid_input, "abc", "def", "Shift_JIS", "ISO-2022-JP", "abc\xFFdef")
  end

  def test_errors
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP", 0)
    src = "\xFF\xFE\x00A\xDC\x00"
    ret = ec.primitive_convert(src, dst="", 10, 0)
    assert_equal("", src)
    assert_equal("", dst)
    assert_equal(:undefined_conversion, ret) # \xFF\xFE is not representable in EUC-JP
    ret = ec.primitive_convert(src, dst="", 10, 0)
    assert_equal("", src)
    assert_equal("A", dst)
    assert_equal(:invalid_input, ret) # \xDC\x00 is invalid as UTF-16BE
    ret = ec.primitive_convert(src, dst="", 10, 0)
    assert_equal("", src)
    assert_equal("", dst)
    assert_equal(:finished, ret)
  end

  def test_universal_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNIVERSAL_NEWLINE)
    ret = ec.primitive_convert(src="abc\r\ndef", dst="", 50, Encoding::Converter::PARTIAL_INPUT)
    assert_equal([:ibuf_empty, "", "abc\ndef"], [ret, src, dst])
    ret = ec.primitive_convert(src="ghi\njkl", dst="", 50, Encoding::Converter::PARTIAL_INPUT)
    assert_equal([:ibuf_empty, "", "ghi\njkl"], [ret, src, dst])
    ret = ec.primitive_convert(src="mno\rpqr", dst="", 50, Encoding::Converter::PARTIAL_INPUT)
    assert_equal([:ibuf_empty, "", "mno\npqr"], [ret, src, dst])
    ret = ec.primitive_convert(src="stu\r", dst="", 50, Encoding::Converter::PARTIAL_INPUT)
    assert_equal([:ibuf_empty, "", "stu\n"], [ret, src, dst])
    ret = ec.primitive_convert(src="\nvwx", dst="", 50, Encoding::Converter::PARTIAL_INPUT)
    assert_equal([:ibuf_empty, "", "vwx"], [ret, src, dst])
  end
end
