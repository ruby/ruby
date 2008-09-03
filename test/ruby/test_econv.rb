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

  def assert_errinfo(e_res, e_enc1, e_enc2, e_error_bytes, e_readagain_bytes, ec)
    assert_equal([e_res, e_enc1, e_enc2,
                  e_error_bytes && e_error_bytes.dup.force_encoding("ASCII-8BIT"), 
                  e_readagain_bytes && e_readagain_bytes.dup.force_encoding("ASCII-8BIT")],
                 ec.primitive_errinfo)
  end

  def test_new
    assert_kind_of(Encoding::Converter, Encoding::Converter.new("UTF-8", "EUC-JP"))
    assert_kind_of(Encoding::Converter, Encoding::Converter.new(Encoding::UTF_8, Encoding::EUC_JP))
  end

  def test_new_fail
    name1 = "encoding-which-is-not-exist-1"
    name2 = "encoding-which-is-not-exist-2"

    assert_raise(Encoding::NoConverter) {
      Encoding::Converter.new(name1, name2)
    }

    encoding_list = Encoding.list.map {|e| e.name }
    assert(!encoding_list.include?(name1))
    assert(!encoding_list.include?(name2))
  end

  def test_get_encoding
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    assert_equal(Encoding::UTF_8, ec.source_encoding)
    assert_equal(Encoding::EUC_JP, ec.destination_encoding)
  end

  def test_result_encoding
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    dst = "".force_encoding("ASCII-8BIT")
    assert_equal(Encoding::ASCII_8BIT, dst.encoding)
    ec.primitive_convert("\u{3042}", dst, nil, 10)
    assert_equal(Encoding::EUC_JP, dst.encoding)
  end

  def test_output_region
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

  def test_nil_source_buffer
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    ret = ec.primitive_convert(nil, dst="", nil, 10)
    assert_equal(:finished, ret)
  end

  def test_nil_destination_bytesize
    ec = Encoding::Converter.new("Shift_JIS", "UTF-8")
    n = 10000
    src = "\xa1".force_encoding("Shift_JIS") * n
    ret = ec.primitive_convert(src, dst="", nil, nil)
    assert_equal(:finished, ret)
    assert_equal("\xEF\xBD\xA1".force_encoding("UTF-8") * n, dst)
  end

  def test_nil_destination_bytesize2
    ec = Encoding::Converter.new("Shift_JIS", "UTF-8")
    n = 10000
    src = "\xa1".force_encoding("Shift_JIS") * n
    ret = ec.primitive_convert(src, dst="")
    assert_equal(:finished, ret)
    assert_equal("\xEF\xBD\xA1".force_encoding("UTF-8") * n, dst)
  end

  def test_nil_destination_bytesize_with_nonnil_byteoffset
    ec = Encoding::Converter.new("Shift_JIS", "UTF-8")
    n = 2000
    src = "\xa1".force_encoding("Shift_JIS") * n
    dst = "abcd" * 2000
    ret = ec.primitive_convert(src, dst, 3, nil)
    assert_equal(:finished, ret)
    assert_equal("abc" + "\xEF\xBD\xA1".force_encoding("UTF-8") * n, dst)
  end

  def test_partial_input
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    ret = ec.primitive_convert(src="", dst="", nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal(:source_buffer_empty, ret)
    ret = ec.primitive_convert(src="", dst="", nil, 10)
    assert_equal(:finished, ret)
  end

  def test_accumulate_dst1
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    a =     ["", "abc\u{3042}def", ec, nil, 1]
    check_ec("a",  "c\u{3042}def", :destination_buffer_full, *a)
    check_ec("ab",  "\u{3042}def", :destination_buffer_full, *a)
    check_ec("abc",         "def", :destination_buffer_full, *a)
    check_ec("abc\xA4",     "def", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2",  "ef", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2d",  "f", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2de",  "", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2def", "", :finished,  *a)
  end

  def test_accumulate_dst2
    ec = Encoding::Converter.new("UTF-8", "EUC-JP")
    a =     ["", "abc\u{3042}def", ec, nil, 2]
    check_ec("ab",  "\u{3042}def", :destination_buffer_full, *a)
    check_ec("abc\xA4",     "def", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2d",  "f", :destination_buffer_full, *a)
    check_ec("abc\xA4\xA2def", "", :finished,  *a)
  end

  def test_eucjp_to_utf8
    assert_econv("", :finished, 100, ["UTF-8", "EUC-JP"], "", "")
    assert_econv("a", :finished, 100, ["UTF-8", "EUC-JP"], "a", "")
  end

  def test_iso2022jp
    assert_econv("", :finished, 100, ["Shift_JIS", "ISO-2022-JP"], "", "")
  end

  def test_iso2022jp_encode
    ec = Encoding::Converter.new("EUC-JP", "ISO-2022-JP")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "a";        check_ec("a",                           "", :source_buffer_empty, *a)
    src << "\xA2";     check_ec("a",                           "", :source_buffer_empty, *a)
    src << "\xA4";     check_ec("a\e$B\"$",                    "", :source_buffer_empty, *a)
    src << "\xA1";     check_ec("a\e$B\"$",                    "", :source_buffer_empty, *a)
    src << "\xA2";     check_ec("a\e$B\"$!\"",                 "", :source_buffer_empty, *a)
    src << "b";        check_ec("a\e$B\"$!\"\e(Bb",            "", :source_buffer_empty, *a)
    src << "\xA2\xA6"; check_ec("a\e$B\"$!\"\e(Bb\e$B\"&",     "", :source_buffer_empty, *a)
    a[-1] = 0;         check_ec("a\e$B\"$!\"\e(Bb\e$B\"&\e(B", "", :finished, *a)
  end

  def test_iso2022jp_decode
    ec = Encoding::Converter.new("ISO-2022-JP", "EUC-JP")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "a";         check_ec("a",                   "", :source_buffer_empty, *a)
    src << "\e";        check_ec("a",                   "", :source_buffer_empty, *a)
    src << "$";         check_ec("a",                   "", :source_buffer_empty, *a)
    src << "B";         check_ec("a",                   "", :source_buffer_empty, *a)
    src << "\x21";      check_ec("a",                   "", :source_buffer_empty, *a)
    src << "\x22";      check_ec("a\xA1\xA2",           "", :source_buffer_empty, *a)
    src << "\n";        check_ec("a\xA1\xA2",           "", :invalid_byte_sequence, *a)
    src << "\x23";      check_ec("a\xA1\xA2",           "", :source_buffer_empty, *a)
    src << "\x24";      check_ec("a\xA1\xA2\xA3\xA4",   "", :source_buffer_empty, *a)
    src << "\e";        check_ec("a\xA1\xA2\xA3\xA4",   "", :source_buffer_empty, *a)
    src << "(";         check_ec("a\xA1\xA2\xA3\xA4",   "", :source_buffer_empty, *a)
    src << "B";         check_ec("a\xA1\xA2\xA3\xA4",   "", :source_buffer_empty, *a)
    src << "c";         check_ec("a\xA1\xA2\xA3\xA4c",  "", :source_buffer_empty, *a)
    src << "\n";        check_ec("a\xA1\xA2\xA3\xA4c\n","", :source_buffer_empty, *a)
  end

  def test_invalid
    assert_econv("", :invalid_byte_sequence,    100, ["UTF-8", "EUC-JP"], "\x80", "")
    assert_econv("a", :invalid_byte_sequence,   100, ["UTF-8", "EUC-JP"], "a\x80", "")
    assert_econv("a", :invalid_byte_sequence,   100, ["UTF-8", "EUC-JP"], "a\x80", "\x80")
    assert_econv("abc", :invalid_byte_sequence, 100, ["UTF-8", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_byte_sequence, 100, ["Shift_JIS", "EUC-JP"], "abc\xFF", "def")
    assert_econv("abc", :invalid_byte_sequence, 100, ["ISO-2022-JP", "EUC-JP"], "abc\xFF", "def")
  end

  def test_invalid2
    ec = Encoding::Converter.new("Shift_JIS", "EUC-JP")
    a =     ["", "abc\xFFdef", ec, nil, 1]
    check_ec("a",  "c\xFFdef", :destination_buffer_full, *a)
    check_ec("ab",  "\xFFdef", :destination_buffer_full, *a)
    check_ec("abc",     "def", :invalid_byte_sequence, *a)
    check_ec("abcd",      "f", :destination_buffer_full, *a)
    check_ec("abcde",      "", :destination_buffer_full, *a)
    check_ec("abcdef",     "", :finished, *a)
  end

  def test_invalid3
    ec = Encoding::Converter.new("Shift_JIS", "EUC-JP")
    a =     ["", "abc\xFFdef", ec, nil, 10]
    check_ec("abc",     "def", :invalid_byte_sequence, *a)
    check_ec("abcdef",     "", :finished, *a)
  end

  def test_invalid4
    ec = Encoding::Converter.new("Shift_JIS", "EUC-JP")
    a =     ["", "abc\xFFdef", ec, nil, 10, Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT]
    check_ec("a", "bc\xFFdef", :output_followed_by_input, *a)
    check_ec("ab", "c\xFFdef", :output_followed_by_input, *a)
    check_ec("abc", "\xFFdef", :output_followed_by_input, *a)
    check_ec("abc",     "def", :invalid_byte_sequence, *a)
    check_ec("abcd",     "ef", :output_followed_by_input, *a)
    check_ec("abcde",     "f", :output_followed_by_input, *a)
    check_ec("abcdef",     "", :output_followed_by_input, *a)
    check_ec("abcdef",     "", :finished, *a)
  end

  def test_invalid_utf16le
    ec = Encoding::Converter.new("UTF-16LE", "UTF-8")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "A";         check_ec("",                            "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\x01";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\x02";      check_ec("A",                           "", :invalid_byte_sequence, *a)
    src << "\x03";      check_ec("A\u{0201}",                   "", :source_buffer_empty, *a)
    src << "\x04";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A\u{0201}\u{0403}",           "", :invalid_byte_sequence, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xdc";      check_ec("A\u{0201}\u{0403}\u{10000}",  "", :source_buffer_empty, *a)
  end

  def test_invalid_utf16be
    ec = Encoding::Converter.new("UTF-16BE", "UTF-8")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "\x00";      check_ec("",                            "", :source_buffer_empty, *a)
    src << "A";         check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",                           "", :source_buffer_empty, *a)
    src << "\x02";      check_ec("A",                           "", :invalid_byte_sequence, *a)
    src << "\x01";      check_ec("A\u{0201}",                   "", :source_buffer_empty, *a)
    src << "\x04";      check_ec("A\u{0201}",                   "", :source_buffer_empty, *a)
    src << "\x03";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xd8";      check_ec("A\u{0201}\u{0403}",           "", :invalid_byte_sequence, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\xdc";      check_ec("A\u{0201}\u{0403}",           "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A\u{0201}\u{0403}\u{10000}",  "", :source_buffer_empty, *a)
  end

  def test_invalid_utf32be
    ec = Encoding::Converter.new("UTF-32BE", "UTF-8")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "\x00";      check_ec("",    "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("",    "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("",    "", :source_buffer_empty, *a)
    src << "A";         check_ec("A",   "", :source_buffer_empty, *a)

    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\xdc";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :invalid_byte_sequence, *a)

    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "B";         check_ec("AB",  "", :source_buffer_empty, *a)

    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)
    src << "C";         check_ec("ABC", "", :source_buffer_empty, *a)
  end

  def test_invalid_utf32le
    ec = Encoding::Converter.new("UTF-32LE", "UTF-8")
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "A";         check_ec("",    "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("",    "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("",    "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)

    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\xdc";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :invalid_byte_sequence, *a)

    src << "B";         check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("A",   "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)

    src << "C";         check_ec("AB",  "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("AB",  "", :source_buffer_empty, *a)
    src << "\x00";      check_ec("ABC", "", :source_buffer_empty, *a)
  end

  def test_errors
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    a =     ["", "\xFF\xFE\x00A\xDC\x00\x00B", ec, nil, 10]
    check_ec("",         "\x00A\xDC\x00\x00B", :undefined_conversion, *a)
    check_ec("A",                     "\x00B", :invalid_byte_sequence, *a) # \xDC\x00 is invalid as UTF-16BE
    check_ec("AB",                         "", :finished, *a)
  end

  def test_errors2
    ec = Encoding::Converter.new("UTF-16BE", "EUC-JP")
    a =     ["", "\xFF\xFE\x00A\xDC\x00\x00B", ec, nil, 10, Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT]
    check_ec("",         "\x00A\xDC\x00\x00B", :undefined_conversion, *a)
    check_ec("A",             "\xDC\x00\x00B", :output_followed_by_input, *a)
    check_ec("A",                     "\x00B", :invalid_byte_sequence, *a)
    check_ec("AB",                         "", :output_followed_by_input, *a)
    check_ec("AB",                         "", :finished, *a)
  end

  def test_universal_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNIVERSAL_NEWLINE_DECODER)
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "abc\r\ndef"; check_ec("abc\ndef",                             "", :source_buffer_empty, *a)
    src << "ghi\njkl";   check_ec("abc\ndefghi\njkl",                     "", :source_buffer_empty, *a)
    src << "mno\rpqr";   check_ec("abc\ndefghi\njklmno\npqr",             "", :source_buffer_empty, *a)
    src << "stu\r";      check_ec("abc\ndefghi\njklmno\npqrstu\n",        "", :source_buffer_empty, *a)
    src << "\nvwx";      check_ec("abc\ndefghi\njklmno\npqrstu\nvwx",     "", :source_buffer_empty, *a)
    src << "\nyz";       check_ec("abc\ndefghi\njklmno\npqrstu\nvwx\nyz", "", :source_buffer_empty, *a)
  end

  def test_universal_newline2
    ec = Encoding::Converter.new("", "", Encoding::Converter::UNIVERSAL_NEWLINE_DECODER)
    a = ["", src="", ec, nil, 50, Encoding::Converter::PARTIAL_INPUT]
    src << "abc\r\ndef"; check_ec("abc\ndef",                             "", :source_buffer_empty, *a)
    src << "ghi\njkl";   check_ec("abc\ndefghi\njkl",                     "", :source_buffer_empty, *a)
    src << "mno\rpqr";   check_ec("abc\ndefghi\njklmno\npqr",             "", :source_buffer_empty, *a)
    src << "stu\r";      check_ec("abc\ndefghi\njklmno\npqrstu\n",        "", :source_buffer_empty, *a)
    src << "\nvwx";      check_ec("abc\ndefghi\njklmno\npqrstu\nvwx",     "", :source_buffer_empty, *a)
    src << "\nyz";       check_ec("abc\ndefghi\njklmno\npqrstu\nvwx\nyz", "", :source_buffer_empty, *a)
  end

  def test_crlf_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CRLF_NEWLINE_ENCODER)
    assert_econv("abc\r\ndef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_crlf_newline2
    ec = Encoding::Converter.new("", "", Encoding::Converter::CRLF_NEWLINE_ENCODER)
    assert_econv("abc\r\ndef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_cr_newline
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::CR_NEWLINE_ENCODER)
    assert_econv("abc\rdef", :finished, 50, ec, "abc\ndef", "")
  end

  def test_cr_newline2
    ec = Encoding::Converter.new("", "", Encoding::Converter::CR_NEWLINE_ENCODER)
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

  def test_errinfo_invalid_euc_jp
    ec = Encoding::Converter.new("EUC-JP", "Shift_JIS")
    ec.primitive_convert(src="\xff", dst="", nil, 10)                       
    assert_errinfo(:invalid_byte_sequence, "EUC-JP", "Shift_JIS", "\xFF", "", ec)
  end

  def test_errinfo_invalid_euc_jp2
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    ec.primitive_convert(src="\xff", dst="", nil, 10)                       
    assert_errinfo(:invalid_byte_sequence, "EUC-JP", "UTF-8", "\xFF", "", ec)
  end

  def test_errinfo_undefined_hiragana
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    ec.primitive_convert(src="\xa4\xa2", dst="", nil, 10)
    assert_errinfo(:undefined_conversion, "UTF-8", "ISO-8859-1", "\xE3\x81\x82", "", ec)
  end

  def test_errinfo_invalid_partial_character
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    ec.primitive_convert(src="\xa4", dst="", nil, 10)
    assert_errinfo(:incomplete_input, "EUC-JP", "UTF-8", "\xA4", "", ec)
  end

  def test_errinfo_valid_partial_character
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    ec.primitive_convert(src="\xa4", dst="", nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_errinfo(:source_buffer_empty, nil, nil, nil, nil, ec)
  end

  def test_errinfo_invalid_utf16be
    ec = Encoding::Converter.new("UTF-16BE", "UTF-8")
    ec.primitive_convert(src="\xd8\x00\x00@", dst="", nil, 10)
    assert_errinfo(:invalid_byte_sequence, "UTF-16BE", "UTF-8", "\xD8\x00", "\x00", ec)
    assert_equal("@", src)
  end

  def test_errinfo_invalid_utf16le
    ec = Encoding::Converter.new("UTF-16LE", "UTF-8")
    ec.primitive_convert(src="\x00\xd8@\x00", dst="", nil, 10)
    assert_errinfo(:invalid_byte_sequence, "UTF-16LE", "UTF-8", "\x00\xD8", "@\x00", ec)
    assert_equal("", src)
  end

  def test_output_iso2022jp
    ec = Encoding::Converter.new("EUC-JP", "ISO-2022-JP")
    ec.primitive_convert(src="\xa1\xa1", dst="", nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!".force_encoding("ISO-2022-JP"), dst)
    assert_equal(nil, ec.insert_output("???"))
    ec.primitive_convert("", dst, nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!\e(B???".force_encoding("ISO-2022-JP"), dst)
    ec.primitive_convert(src="\xa1\xa2", dst, nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!\e(B???\e$B!\"".force_encoding("ISO-2022-JP"), dst)

    assert_equal(nil, ec.insert_output("\xA1\xA1".force_encoding("EUC-JP")))
    ec.primitive_convert("", dst, nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!\e(B???\e$B!\"!!".force_encoding("ISO-2022-JP"), dst) 

    ec.primitive_convert(src="\xa1\xa3", dst, nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!\e(B???\e$B!\"!!!\#".force_encoding("ISO-2022-JP"), dst)

    assert_equal(nil, ec.insert_output("\u3042"))
    ec.primitive_convert("", dst, nil, 10, Encoding::Converter::PARTIAL_INPUT)
    assert_equal("\e$B!!\e(B???\e$B!\"!!!\#$\"".force_encoding("ISO-2022-JP"), dst)

    assert_raise(Encoding::ConversionUndefined) {
      ec.insert_output("\uFFFD")
    }

    assert_equal("\e$B!!\e(B???\e$B!\"!!!\#$\"".force_encoding("ISO-2022-JP"), dst)

    ec.primitive_convert("", dst, nil, 10)
    assert_equal("\e$B!!\e(B???\e$B!\"!!!\#$\"\e(B".force_encoding("ISO-2022-JP"), dst)
  end

  def test_exc_invalid
    err = assert_raise(Encoding::InvalidByteSequence) {
      "abc\xa4def".encode("ISO-8859-1", "EUC-JP")
    }
    assert_equal("EUC-JP", err.source_encoding_name)
    assert_equal("UTF-8", err.destination_encoding_name)
    assert_equal(Encoding::EUC_JP, err.source_encoding)
    assert_equal(Encoding::UTF_8, err.destination_encoding)
    assert_equal("\xA4".force_encoding("ASCII-8BIT"), err.error_bytes)
    assert_equal("d", err.readagain_bytes)
    assert_equal(false, err.incomplete_input?)
  end

  def test_exc_incomplete
    err = assert_raise(Encoding::InvalidByteSequence) {
      "abc\xa4".encode("ISO-8859-1", "EUC-JP")
    }
    assert_equal("EUC-JP", err.source_encoding_name)
    assert_equal("UTF-8", err.destination_encoding_name)
    assert_equal(Encoding::EUC_JP, err.source_encoding)
    assert_equal(Encoding::UTF_8, err.destination_encoding)
    assert_equal("\xA4".force_encoding("ASCII-8BIT"), err.error_bytes)
    assert_equal(nil, err.readagain_bytes)
    assert_equal(true, err.incomplete_input?)
  end

  def test_exc_undef
    err = assert_raise(Encoding::ConversionUndefined) {
      "abc\xa4\xa2def".encode("ISO-8859-1", "EUC-JP")
    }
    assert_equal("UTF-8", err.source_encoding_name)
    assert_equal("ISO-8859-1", err.destination_encoding_name)
    assert_equal(Encoding::UTF_8, err.source_encoding)
    assert_equal(Encoding::ISO_8859_1, err.destination_encoding)
    assert_equal("\u{3042}", err.error_char)
  end

  def test_putback
    ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
    ret = ec.primitive_convert(src="abc\xa1def", dst="", nil, 10)
    assert_equal(:invalid_byte_sequence, ret)
    assert_equal(["abc", "ef"], [dst, src])
    src = ec.putback + src
    assert_equal(["abc", "def"], [dst, src])
    ret = ec.primitive_convert(src, dst, nil, 10)
    assert_equal(:finished, ret)
    assert_equal(["abcdef", ""], [dst, src])
  end

  def test_putback2
    ec = Encoding::Converter.new("utf-16le", "euc-jp")
    ret = ec.primitive_convert(src="\x00\xd8\x21\x00", dst="", nil, nil)
    assert_equal(:invalid_byte_sequence, ret)
    assert_equal("\x00".force_encoding("utf-16le"), ec.putback(1))
    assert_equal("\x21".force_encoding("utf-16le"), ec.putback(1))
    assert_equal("", ec.putback(1))
  end

  def test_invalid_replace
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::INVALID_REPLACE)
    ret = ec.primitive_convert(src="abc\x80def", dst="", nil, 100)
    assert_equal(:finished, ret)
    assert_equal("", src)
    assert_equal("abc?def", dst)
  end

  def test_invalid_ignore
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::INVALID_IGNORE)
    ret = ec.primitive_convert(src="abc\x80def", dst="", nil, 100)
    assert_equal(:finished, ret)
    assert_equal("", src)
    assert_equal("abcdef", dst)
  end

  def test_undef_replace
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNDEF_REPLACE)
    ret = ec.primitive_convert(src="abc\u{fffd}def", dst="", nil, 100)
    assert_equal(:finished, ret)
    assert_equal("", src)
    assert_equal("abc?def", dst)
  end

  def test_undef_ignore
    ec = Encoding::Converter.new("UTF-8", "EUC-JP", Encoding::Converter::UNDEF_IGNORE)
    ret = ec.primitive_convert(src="abc\u{fffd}def", dst="", nil, 100)
    assert_equal(:finished, ret)
    assert_equal("", src)
    assert_equal("abcdef", dst)
  end

  def test_noconv
    ec = Encoding::Converter.new("", "")
    assert_equal(nil, ec.source_encoding)
    assert_equal(nil, ec.destination_encoding)
    assert_equal([:source_buffer_empty, nil, nil, nil, nil], ec.primitive_errinfo)
    a =     ["", "abcdefg", ec, nil, 2]
    check_ec("ab", "cdefg", :destination_buffer_full, *a)
    check_ec("abcd", "efg", :destination_buffer_full, *a)
    check_ec("abcdef", "g", :destination_buffer_full, *a)
    check_ec("abcdefg", "", :finished, *a)
  end

  def test_noconv_partial
    ec = Encoding::Converter.new("", "")
    a =     ["", "abcdefg", ec, nil, 2, Encoding::Converter::PARTIAL_INPUT]
    check_ec("ab", "cdefg", :destination_buffer_full, *a)
    check_ec("abcd", "efg", :destination_buffer_full, *a)
    check_ec("abcdef", "g", :destination_buffer_full, *a)
    check_ec("abcdefg", "", :source_buffer_empty, *a)
  end

  def test_noconv_output_followed_by_input
    ec = Encoding::Converter.new("", "")
    a =     ["", "abcdefg", ec, nil, 2, Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT]
    check_ec("a", "bcdefg", :output_followed_by_input, *a)
    check_ec("ab", "cdefg", :output_followed_by_input, *a)
    check_ec("abc", "defg", :output_followed_by_input, *a)
    check_ec("abcd", "efg", :output_followed_by_input, *a)
    check_ec("abcde", "fg", :output_followed_by_input, *a)
    check_ec("abcdef", "g", :output_followed_by_input, *a)
    check_ec("abcdefg", "", :output_followed_by_input, *a)
    check_ec("abcdefg", "", :finished, *a)
  end

  def test_noconv_insert_output
    ec = Encoding::Converter.new("", "")
    ec.insert_output("xyz")
    ret = ec.primitive_convert(src="abc", dst="", nil, 20)
    assert_equal(:finished, ret)
    assert_equal(["xyzabc", ""], [dst, src])
  end

  def test_convert
    ec = Encoding::Converter.new("utf-8", "euc-jp")
    assert_raise(Encoding::InvalidByteSequence) { ec.convert("a\x80") }
    assert_raise(Encoding::ConversionUndefined) { ec.convert("\ufffd") }
    ret = ec.primitive_convert(nil, "", nil, nil)
    assert_equal(:finished, ret)
    assert_raise(ArgumentError) { ec.convert("a") }
  end

  def test_finish_iso2022jp
     ec = Encoding::Converter.new("utf-8", "iso-2022-jp")
     assert_equal("\e$B$\"".force_encoding("iso-2022-jp"), ec.convert("\u3042"))
     assert_equal("\e(B".force_encoding("iso-2022-jp"), ec.finish)

  end

  def test_finish_incomplete_error
    ec = Encoding::Converter.new("utf-8", "euc-jp")
    ec.convert("\xEF")
    assert_raise(Encoding::InvalidByteSequence) { ec.finish }
  end

  def test_last_error1
    ec = Encoding::Converter.new("sjis", "euc-jp")
    assert_equal(nil, ec.last_error)
    assert_equal(:incomplete_input, ec.primitive_convert(src="fo\x81", dst="", nil, nil))
    assert_kind_of(Encoding::InvalidByteSequence, ec.last_error)
  end

  def test_last_error2
    ec = Encoding::Converter.new("sjis", "euc-jp")
    assert_equal("fo", ec.convert(src="fo\x81"))
    assert_raise(Encoding::InvalidByteSequence) { ec.finish }
    assert_kind_of(Encoding::InvalidByteSequence, ec.last_error)
  end

  def test_us_ascii
    ec = Encoding::Converter.new("UTF-8", "US-ASCII")
    ec.primitive_convert(src="\u{3042}", dst="")
    err = ec.last_error
    assert_kind_of(Encoding::ConversionUndefined, err)
    assert_equal("\u{3042}", err.error_char)
  end

  def test_88591
    ec = Encoding::Converter.new("UTF-8", "ISO-8859-1")
    ec.primitive_convert(src="\u{3042}", dst="")
    err = ec.last_error
    assert_kind_of(Encoding::ConversionUndefined, err)
    assert_equal("\u{3042}", err.error_char)
  end

  def test_get_replacement
    ec = Encoding::Converter.new("euc-jp", "iso-8859-1")
    assert_equal("?", ec.replacement)

    ec = Encoding::Converter.new("euc-jp", "utf-8")
    assert_equal("\uFFFD", ec.replacement)
  end

  def test_set_replacement
    ec = Encoding::Converter.new("utf-8", "us-ascii", Encoding::Converter::UNDEF_REPLACE)
    ec.replacement = "<undef>"
    assert_equal("a <undef> b", ec.convert("a \u3042 b"))
  end

  def test_econv_new_hash
    ec = Encoding::Converter.new("utf-8", "us-ascii", :undef => :replace)  
    assert_equal("a ? b", ec.convert("a \u3042 b"))
    ec = Encoding::Converter.new("utf-8", "us-ascii", :undef => :replace, :replace => "X")  
    assert_equal("a X b", ec.convert("a \u3042 b"))
  end
end
