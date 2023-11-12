# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class EncodingTest < TestCase
    [
      "US-ASCII",
      "ASCII-8BIT",
      "Big5",
      "CP850",
      "CP852",
      "CP51932",
      "EUC-JP",
      "GBK",
      "ISO-8859-1",
      "ISO-8859-2",
      "ISO-8859-3",
      "ISO-8859-4",
      "ISO-8859-5",
      "ISO-8859-6",
      "ISO-8859-7",
      "ISO-8859-8",
      "ISO-8859-9",
      "ISO-8859-10",
      "ISO-8859-11",
      "ISO-8859-13",
      "ISO-8859-14",
      "ISO-8859-15",
      "ISO-8859-16",
      "KOI8-R",
      "Shift_JIS",
      "UTF-8",
      "UTF8-MAC",
      "Windows-1250",
      "Windows-1251",
      "Windows-1252",
      "Windows-1253",
      "Windows-1254",
      "Windows-1255",
      "Windows-1256",
      "Windows-1257",
      "Windows-1258",
      "Windows-31J"
    ].each do |canonical_name|
      encoding = Encoding.find(canonical_name)

      encoding.names.each do |name|
        # Even though UTF-8-MAC is an alias for UTF8-MAC, CRuby treats it as
        # UTF-8. So we'll skip this test.
        next if name == "UTF-8-MAC"

        define_method "test_encoding_#{name}" do
          result = Prism.parse("# encoding: #{name}\n'string'")
          actual = result.value.statements.body.first.unescaped.encoding
          assert_equal encoding, actual
        end
      end
    end

    def test_coding
      result = Prism.parse("# coding: utf-8\n'string'")
      actual = result.value.statements.body.first.unescaped.encoding
      assert_equal Encoding.find("utf-8"), actual
    end

    def test_coding_with_whitespace
      result = Prism.parse("# coding \t \r  \v   :     \t \v    \r   ascii-8bit \n'string'")
      actual = result.value.statements.body.first.unescaped.encoding
      assert_equal Encoding.find("ascii-8bit"), actual
    end


    def test_emacs_style
      result = Prism.parse("# -*- coding: utf-8 -*-\n'string'")
      actual = result.value.statements.body.first.unescaped.encoding
      assert_equal Encoding.find("utf-8"), actual
    end

    # This test may be a little confusing. Basically when we use our strpbrk, it
    # takes into account the encoding of the file.
    def test_strpbrk_multibyte
      result = Prism.parse(<<~RUBY)
        # encoding: Shift_JIS
        %w[\x81\x5c]
      RUBY

      assert(result.errors.empty?)
      assert_equal(
        (+"\x81\x5c").force_encoding(Encoding::Shift_JIS),
        result.value.statements.body.first.elements.first.unescaped
      )
    end

    def test_utf_8_variations
      %w[
        utf-8-unix
        utf-8-dos
        utf-8-mac
        utf-8-*
      ].each do |encoding|
        result = Prism.parse("# coding: #{encoding}\n'string'")
        actual = result.value.statements.body.first.unescaped.encoding
        assert_equal Encoding.find("utf-8"), actual
      end
    end

    def test_first_lexed_token
      encoding = Prism.lex("# encoding: ascii-8bit").value[0][0].value.encoding
      assert_equal Encoding.find("ascii-8bit"), encoding
    end

    def test_slice_encoding
      slice = Prism.parse("# encoding: Shift_JIS\nア").value.slice
      assert_equal (+"ア").force_encoding(Encoding::SHIFT_JIS), slice
      assert_equal Encoding::SHIFT_JIS, slice.encoding
    end
  end
end
