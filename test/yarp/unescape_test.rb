# frozen_string_literal: true

require "test_helper"

module UnescapeTest
  class UnescapeNoneTest < Test::Unit::TestCase
    test "backslash" do
      assert_unescape_none("\\")
    end

    test "single quote" do
      assert_unescape_none("'")
    end

    private

    def assert_unescape_none(source)
      assert_equal(source, YARP.unescape_none(source))
    end
  end

  class UnescapeMinimalTest < Test::Unit::TestCase
    test "backslash" do
      assert_unescape_minimal("\\", "\\\\")
    end

    test "single quote" do
      assert_unescape_minimal("'", "\\'")
    end

    test "single char" do
      assert_unescape_minimal("\\a", "\\a")
    end

    private

    def assert_unescape_minimal(expected, source)
      assert_equal(expected, YARP.unescape_minimal(source))
    end
  end

  class UnescapeAllTest < Test::Unit::TestCase
    test "backslash" do
      assert_unescape_all("\\", "\\\\")
    end

    test "single quote" do
      assert_unescape_all("'", "\\'")
    end

    test "single char" do
      assert_unescape_all("\a", "\\a")
      assert_unescape_all("\b", "\\b")
      assert_unescape_all("\e", "\\e")
      assert_unescape_all("\f", "\\f")
      assert_unescape_all("\n", "\\n")
      assert_unescape_all("\r", "\\r")
      assert_unescape_all("\s", "\\s")
      assert_unescape_all("\t", "\\t")
      assert_unescape_all("\v", "\\v")
    end

    test "octal" do
      assert_unescape_all("\a", "\\7")
      assert_unescape_all("#", "\\43")
      assert_unescape_all("a", "\\141")
    end

    test "hexadecimal" do
      assert_unescape_all("\a", "\\x7")
      assert_unescape_all("#", "\\x23")
      assert_unescape_all("a", "\\x61")
    end

    test "deletes" do
      assert_unescape_all("\x7f", "\\c?")
      assert_unescape_all("\x7f", "\\C-?")
    end

    test "unicode codepoint" do
      assert_unescape_all("a", "\\u0061")
      assert_unescape_all("Ā", "\\u0100", "UTF-8")
      assert_unescape_all("က", "\\u1000", "UTF-8")
      assert_unescape_all("တ", "\\u1010", "UTF-8")

      assert_nil(YARP.unescape_all("\\uxxxx"))
    end

    test "unicode codepoints" do
      assert_unescape_all("a", "\\u{61}")
      assert_unescape_all("Ā", "\\u{0100}", "UTF-8")
      assert_unescape_all("က", "\\u{1000}", "UTF-8")
      assert_unescape_all("တ", "\\u{1010}", "UTF-8")
      assert_unescape_all("𐀀", "\\u{10000}", "UTF-8")
      assert_unescape_all("𐀐", "\\u{10010}", "UTF-8")
      assert_unescape_all("aĀကတ𐀀𐀐", "\\u{ 61\s100\n1000\t1010\r10000\v10010 }", "UTF-8")

      assert_nil(YARP.unescape_all("\\u{110000}"))
      assert_nil(YARP.unescape_all("\\u{110000 110001 110002}"))
    end

    test "control characters" do
      each_printable do |chr|
        byte = eval("\"\\c#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\c#{chr}")

        byte = eval("\"\\C-#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\C-#{chr}")
      end
    end

    test "meta characters" do
      each_printable do |chr|
        byte = eval("\"\\M-#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\M-#{chr}")
      end
    end

    test "meta control characters" do
      each_printable do |chr|
        byte = eval("\"\\M-\\c#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\M-\\c#{chr}")

        byte = eval("\"\\M-\\C-#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\M-\\C-#{chr}")

        byte = eval("\"\\c\\M-#{chr}\"").bytes.first
        assert_unescape_all(byte.chr, "\\c\\M-#{chr}")
      end
    end

    test "escaping normal characters" do
      assert_unescape_all("d", "\\d")
      assert_unescape_all("g", "\\g")
    end

    private

    def assert_unescape_all(expected, source, forced_encoding = nil)
      result = YARP.unescape_all(source)
      result.force_encoding(forced_encoding) if forced_encoding
      assert_equal(expected, result)
    end

    def each_printable
      (1..127).each do |ord|
        chr = ord.chr
        yield chr if chr.match?(/[[:print:]]/) && chr != " " && chr != "\\"
      end
    end
  end
end
