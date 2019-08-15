# frozen_string_literal: false
require 'test/unit'

class TestUTF32 < Test::Unit::TestCase
  def encdump(str)
    d = str.dump
    if /\.force_encoding\("[A-Za-z0-9.:_+-]*"\)\z/ =~ d
      d
    else
      "#{d}.force_encoding(#{str.encoding.name.dump})"
    end
  end

  def assert_str_equal(expected, actual, message=nil)
    full_message = build_message(message, <<EOT)
#{encdump expected} expected but not equal to
#{encdump actual}.
EOT
    assert_equal(expected, actual, full_message)
  end

  def test_substr
    assert_str_equal(
      "abcdefgh".force_encoding("utf-32le"),
      "abcdefgh".force_encoding("utf-32le")[0,3])
    assert_str_equal(
      "abcdefgh".force_encoding("utf-32be"),
      "abcdefgh".force_encoding("utf-32be")[0,3])
  end

  def test_mbc_len
    al = "abcdefghijkl".force_encoding("utf-32le").each_char.to_a
    ab = "abcdefghijkl".force_encoding("utf-32be").each_char.to_a
    assert_equal("abcd".force_encoding("utf-32le"), al.shift)
    assert_equal("efgh".force_encoding("utf-32le"), al.shift)
    assert_equal("ijkl".force_encoding("utf-32le"), al.shift)
    assert_equal("abcd".force_encoding("utf-32be"), ab.shift)
    assert_equal("efgh".force_encoding("utf-32be"), ab.shift)
    assert_equal("ijkl".force_encoding("utf-32be"), ab.shift)
  end

  def ascii_to_utf16le(s)
    s.unpack("C*").map {|x| [x,0,0,0] }.flatten.pack("C*").force_encoding("utf-32le")
  end

  def ascii_to_utf16be(s)
    s.unpack("C*").map {|x| [0,0,0,x] }.flatten.pack("C*").force_encoding("utf-32be")
  end

  def test_mbc_newline
    al = ascii_to_utf16le("foo\nbar\nbaz\n").lines.to_a
    ab = ascii_to_utf16be("foo\nbar\nbaz\n").lines.to_a

    assert_equal(ascii_to_utf16le("foo\n"), al.shift)
    assert_equal(ascii_to_utf16le("bar\n"), al.shift)
    assert_equal(ascii_to_utf16le("baz\n"), al.shift)
    assert_equal(ascii_to_utf16be("foo\n"), ab.shift)
    assert_equal(ascii_to_utf16be("bar\n"), ab.shift)
    assert_equal(ascii_to_utf16be("baz\n"), ab.shift)

    sl = "a\0".force_encoding("utf-32le")
    sb = "a\0".force_encoding("utf-32be")
    assert_equal(sl, sl.chomp)
    assert_equal(sb, sb.chomp)
  end

  def test_mbc_to_code
    sl = "a\0\0\0".force_encoding("utf-32le")
    sb = "\0\0\0a".force_encoding("utf-32be")
    assert_equal("a".ord, sl.ord)
    assert_equal("a".ord, sb.ord)
  end

  def utf8_to_utf32(s, e)
    s.chars.map {|c| c.ord.chr(e) }.join
  end

  def test_mbc_case_fold
    rl = Regexp.new(utf8_to_utf32("^(\u3042)(a)\\1\\2$", "utf-32le"), "i")
    rb = Regexp.new(utf8_to_utf32("^(\u3042)(a)\\1\\2$", "utf-32be"), "i")
    assert_equal(Encoding.find("utf-32le"), rl.encoding)
    assert_equal(Encoding.find("utf-32be"), rb.encoding)
    assert_match(rl, utf8_to_utf32("\u3042a\u3042a", "utf-32le"))
    assert_match(rb, utf8_to_utf32("\u3042a\u3042a", "utf-32be"))
  end

  def test_code_to_mbc
    sl = "a\0\0\0".force_encoding("utf-32le")
    sb = "\0\0\0a".force_encoding("utf-32be")
    assert_equal(sl, "a".ord.chr("utf-32le"))
    assert_equal(sb, "a".ord.chr("utf-32be"))
  end

  def test_utf32be_valid_encoding
    all_assertions do |a|
      [
        "\x00\x00\x00\x00",
        "\x00\x00\x00a",
        "\x00\x00\x30\x40",
        "\x00\x00\xd7\xff",
        "\x00\x00\xe0\x00",
        "\x00\x00\xff\xff",
        "\x00\x10\xff\xff",
      ].each {|s|
        s.force_encoding("utf-32be")
        a.for(s) {
          assert_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
      [
        "a",
        "\x00a",
        "\x00\x00a",
        "\x00\x00\xd8\x00",
        "\x00\x00\xdb\xff",
        "\x00\x00\xdc\x00",
        "\x00\x00\xdf\xff",
        "\x00\x11\x00\x00",
      ].each {|s|
        s.force_encoding("utf-32be")
        a.for(s) {
          assert_not_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
    end
  end

  def test_utf32le_valid_encoding
    all_assertions do |a|
      [
        "\x00\x00\x00\x00",
        "a\x00\x00\x00",
        "\x40\x30\x00\x00",
        "\xff\xd7\x00\x00",
        "\x00\xe0\x00\x00",
        "\xff\xff\x00\x00",
        "\xff\xff\x10\x00",
      ].each {|s|
        s.force_encoding("utf-32le")
        a.for(s) {
          assert_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
      [
        "a",
        "a\x00",
        "a\x00\x00",
        "\x00\xd8\x00\x00",
        "\xff\xdb\x00\x00",
        "\x00\xdc\x00\x00",
        "\xff\xdf\x00\x00",
        "\x00\x00\x11\x00",
      ].each {|s|
        s.force_encoding("utf-32le")
        a.for(s) {
          assert_not_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
    end
  end
end

