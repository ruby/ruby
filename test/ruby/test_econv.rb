require 'test/unit'

class TestEncodingConverter < Test::Unit::TestCase
  def check_ec(edst, esrc, eres, dst, src, ec, off, len, flags=0)
    res = ec.primitive_convert(src, dst, off, len, flags)
    assert_equal([edst.dup.force_encoding("ASCII-8BIT"),
                  esrc.dup.force_encoding("ASCII-8BIT"),
                  eres],
                 [dst.dup.force_encoding("ASCII-8BIT"),
                  src.dup.force_encoding("ASCII-8BIT"),
                  res])
  end

  def assert_econv(converted, eres, obuf_bytesize, ec, consumed, rest, flags=0)
    ec = Encoding::Converter.new(*ec) if Array === ec
    i = consumed + rest
    o = ""
    ret = ec.primitive_convert(i, o, 0, obuf_bytesize, flags)
    assert_equal([converted,    eres,       rest],
                 [o,            ret,           i])
  end

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

  def test_accumulate_dst1
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    a =     ["", "abc\u{3042}def", ec, nil, 1]
    check_ec("a",  "c\u{3042}def", :obuf_full, *a)
    check_ec("ab",  "\u{3042}def", :obuf_full, *a)
    check_ec("abc",         "def", :obuf_full, *a)
    check_ec("abc\xA4",     "def", :obuf_full, *a)
    check_ec("abc\xA4\xA2",  "ef", :obuf_full, *a)
    check_ec("abc\xA4\xA2d",  "f", :obuf_full, *a)
    check_ec("abc\xA4\xA2de",  "", :obuf_full, *a)
    check_ec("abc\xA4\xA2def", "", :finished,  *a)
  end

  def test_accumulate_dst2
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    a =     ["", "abc\u{3042}def", ec, nil, 2]
    check_ec("ab",  "\u{3042}def", :obuf_full, *a)
    check_ec("abc\xA4",     "def", :obuf_full, *a)
    check_ec("abc\xA4\xA2d",  "f", :obuf_full, *a)
    check_ec("abc\xA4\xA2def", "", :finished,  *a)
  end

  def test_eucjp_to_utf8
    assert_econv("", :finished, 100, ["UTF-8", "EUC-JP"], "", "")
    assert_econv("a", :finished, 100, ["UTF-8", "EUC-JP"], "a", "")
  end

  def test_iso2022jp
    assert_econv("", :finished, 100, ["Shift_JIS", "ISO-2022-JP"], "", "")
  end

  def test_iso2022jp_outstream
    ec = Encoding::Converter.new("EUC-JP", "ISO-2022-JP")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "a";        check_ec("a",                           "", :ibuf_empty, *a)
    src << "\xA2";     check_ec("a",                           "", :ibuf_empty, *a)
    src << "\xA4";     check_ec("a\e$B\"$",                    "", :ibuf_empty, *a)
    src << "\xA1";     check_ec("a\e$B\"$",                    "", :ibuf_empty, *a)
    src << "\xA2";     check_ec("a\e$B\"$!\"",                 "", :ibuf_empty, *a)
    src << "b";        check_ec("a\e$B\"$!\"\e(Bb",            "", :ibuf_empty, *a)
    src << "\xA2\xA6"; check_ec("a\e$B\"$!\"\e(Bb\e$B\"&",     "", :ibuf_empty, *a)
    a[-1] = 0;         check_ec("a\e$B\"$!\"\e(Bb\e$B\"&\e(B", "", :finished, *a)
  end

  def test_invalid
    assert_econv("", :invalid_input,    100, ["UTF-8", "EUC-JP"], "\x80", "")
    assert_econv("a", :invalid_input,   100, ["UTF-8", "EUC-JP"], "a\x80", "")
    assert_econv("a", :invalid_input,   100, ["UTF-8", "EUC-JP"], "a\x80", "\x80")
    assert_econv("abc", :invalid_input, 100, ["UTF-8", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_input, 100, ["Shift_JIS", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_input, 100, ["ISO-2022-JP", "EUC-JP"], "abc\xFF", "def")
  end

  def test_invalid2
    ec = Encoding::Converter.new("Shift_JIS", "EUC-JP")
    a =     ["", "abc\xFFdef", ec, nil, 1]
    check_ec("a",       "def", :obuf_full, *a)
    check_ec("ab",      "def", :obuf_full, *a)
    check_ec("abc",     "def", :invalid_input, *a)
    check_ec("abcd",       "", :obuf_full, *a)
    check_ec("abcde",      "", :obuf_full, *a)
    check_ec("abcdef",     "", :finished, *a)
  end

  def test_errors
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    a =     ["", "\xFF\xFE\x00A\xDC\x00\x00B", ec, nil, 10]
    check_ec("",                      "\x00B", :undefined_conversion, *a)
    check_ec("A",                     "\x00B", :invalid_input, *a) # \xDC\x00 is invalid as UTF-16BE
    check_ec("AB",                         "", :finished, *a)
  end

  def test_errors2
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    a =     ["", "\xFF\xFE\x00A\xDC\x00\x00B", ec, nil, 10, Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT]
    check_ec("",         "\x00A\xDC\x00\x00B", :undefined_conversion, *a)
    check_ec("A",             "\xDC\x00\x00B", :output_followed_by_input, *a)
    check_ec("A",                     "\x00B", :invalid_input, *a)
    check_ec("AB",                         "", :output_followed_by_input, *a)
    check_ec("AB",                         "", :finished, *a)
  end

  def test_universal_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNIVERSAL_NEWLINE)
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "abc\r\ndef"; check_ec("abc\ndef",                             "", :ibuf_empty, *a)
    src << "ghi\njkl";   check_ec("abc\ndefghi\njkl",                     "", :ibuf_empty, *a)
    src << "mno\rpqr";   check_ec("abc\ndefghi\njklmno\npqr",             "", :ibuf_empty, *a)
    src << "stu\r";      check_ec("abc\ndefghi\njklmno\npqrstu\n",        "", :ibuf_empty, *a)
    src << "\nvwx";      check_ec("abc\ndefghi\njklmno\npqrstu\nvwx",     "", :ibuf_empty, *a)
    src << "\nyz";       check_ec("abc\ndefghi\njklmno\npqrstu\nvwx\nyz", "", :ibuf_empty, *a)
  end

  def test_crlf_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CRLF_NEWLINE)
    assert_econv("abc\r\ndef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_cr_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CR_NEWLINE)
    assert_econv("abc\rdef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_output_followed_by_input
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    a =     ["",  "abc\u{3042}def", ec, nil, 100, Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT]
    check_ec("a",  "bc\u{3042}def", :output_followed_by_input, *a)
    check_ec("ab",  "c\u{3042}def", :output_followed_by_input, *a)
    check_ec("abc",  "\u{3042}def", :output_followed_by_input, *a)
    check_ec("abc\xA4\xA2",  "def", :output_followed_by_input, *a)
    check_ec("abc\xA4\xA2d",  "ef", :output_followed_by_input, *a)
    check_ec("abc\xA4\xA2de",  "f", :output_followed_by_input, *a)
    check_ec("abc\xA4\xA2def",  "", :output_followed_by_input, *a)
    check_ec("abc\xA4\xA2def",  "", :finished, *a)
  end
end
