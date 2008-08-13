require 'test/unit'

class TestEncodingConverter < Test::Unit::TestCase
  def test_output_area
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    ec.primitive_convert(src="a", dst="b", nil, 1, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("ba", dst)
    ec.primitive_convert(src="a", dst="b", 0, 1, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("a", dst)
    ec.primitive_convert(src="a", dst="b", 1, 1, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("ba", dst)
    assert_raise(ArgumentError) {
      ec.primitive_convert(src="a", dst="b", 2, 1, Encoding::Converter::PARTIAL_INPUT)
    }
    assert_raise(ArgumentError) {
      ec.primitive_convert(src="a", dst="b", -1, 1, Encoding::Converter::PARTIAL_INPUT)
    }
    assert_raise(ArgumentError) {
      ec.primitive_convert(src="a", dst="b", 1, -1, Encoding::Converter::PARTIAL_INPUT)
    }
  end

  def test_accumulate_dst
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    src = "abcdef"
    dst = ""
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["a", "cdef"], [dst, src])
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["ab", "def"], [dst, src])
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["abc", "ef"], [dst, src])
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["abcd", "f"], [dst, src])
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["abcde", ""], [dst, src])
    ec.primitive_convert(src, dst, nil, 1)
    assert_equal(["abcdef", ""], [dst, src])
  end

  def assert_econv_loop(ret_expected, dst_expected, src_expected, to, from, src, opt={})
    opt[:obuf_off] ||= 0
    opt[:obuf_len] ||= 100
    src = src.dup
    ec = Encoding::Converter.new(from, to)
    dst = ''
    while true
      ret = ec.primitive_convert(src, dst, nil, opt[:obuf_len])
      #p [ret, dst, src]
      break if ret != :obuf_full
    end
    assert_equal([ret_expected, dst_expected, src_expected], [ret, dst, src])
  end

  def assert_econv(converted, expected, obuf_bytesize, ec, consumed, rest, flags=0)
    ec = Encoding::Converter.new(*ec) if Array === ec
    i = consumed + rest
    o = ""
    ret = ec.primitive_convert(i, o, 0, obuf_bytesize, flags)
    assert_equal([converted,    expected,       rest],
                 [o,            ret,            i])
  end

  def test_eucjp_to_utf8
    assert_econv("", :finished, 100, ["UTF-8", "EUC-JP"], "", "")
    assert_econv("a", :finished, 100, ["UTF-8", "EUC-JP"], "a", "")
  end

  def test_iso2022jp
    assert_econv("", :finished, 100, ["Shift_JIS", "ISO-2022-JP"], "", "")
  end

  def test_invalid
    assert_econv("", :invalid_input,    100, ["UTF-8", "EUC-JP"], "\x80", "")
    assert_econv("a", :invalid_input,   100, ["UTF-8", "EUC-JP"], "a\x80", "")
    assert_econv("a", :invalid_input,   100, ["UTF-8", "EUC-JP"], "a\x80", "\x80")
    assert_econv("abc", :invalid_input, 100, ["UTF-8", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_input, 100, ["Shift_JIS", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_input, 100, ["ISO-2022-JP", "EUC-JP"], "abc\xFF", "def")

    assert_econv_loop(:invalid_input, "abc", "def", "EUC-JP", "Shift_JIS", "abc\xFFdef", :obuf_len=>1)
  end

  def test_errors
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    assert_econv("", :undefined_conversion, 10, ec, "\xFF\xFE\x00A\xDC\x00", "\x00B")
    assert_econv("A", :invalid_input,       10, ec, "", "\x00B") # \xDC\x00 is invalid as UTF-16BE
    assert_econv("B", :finished,            10, ec, "\x00B", "")
  end

  def test_universal_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNIVERSAL_NEWLINE)
    assert_econv("abc\ndef", :ibuf_empty, 50, ec, "abc\r\ndef", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv("ghi\njkl", :ibuf_empty, 50, ec, "ghi\njkl", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv("mno\npqr", :ibuf_empty, 50, ec, "mno\rpqr", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv("stu\n", :ibuf_empty,    50, ec, "stu\r", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv("vwx", :ibuf_empty,      50, ec, "\nvwx", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv("\nyz", :ibuf_empty,     50, ec, "\nyz", "", Encoding::Converter::PARTIAL_INPUT)
  end

  def test_crlf_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CRLF_NEWLINE)
    assert_econv("abc\r\ndef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_cr_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CR_NEWLINE)
    assert_econv("abc\rdef", :finished, 50, ec, "abc\ndef", "")
  end
end
