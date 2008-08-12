require 'test/unit'

class TestEncodingConverter < Test::Unit::TestCase
  def assert_econv(ret_expected, dst_expected, src_expected, to, from, src, opt={})
    opt[:obuf_len] ||= 100
    src = src.dup
    ec = Encoding::Converter.new(from, to)
    dst = ''
    while true
      ret = ec.primitive_convert(src, dst2=" "*opt[:obuf_len], 0)
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
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    src = "\xFF\xFE\x00A\xDC\x00"
    ret = ec.primitive_convert(src, dst=" "*10, 0)
    assert_equal("", src)
    assert_equal("", dst)
    assert_equal(:undefined_conversion, ret)
    ret = ec.primitive_convert(src, dst=" "*10, 0)
    assert_equal("", src)
    assert_equal("A", dst)
    assert_equal(:invalid_input, ret)
    ret = ec.primitive_convert(src, dst=" "*10, 0)
    assert_equal("", src)
    assert_equal("", dst)
    assert_equal(:finished, ret)
  end
end
