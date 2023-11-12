# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class EncodingTest < TestCase
    [
      Encoding::ASCII,
      Encoding::ASCII_8BIT,
      Encoding::Big5,
      Encoding::CP51932,
      Encoding::CP850,
      Encoding::CP852,
      Encoding::CP855,
      Encoding::EUC_JP,
      Encoding::GBK,
      Encoding::IBM437,
      Encoding::ISO_8859_1,
      Encoding::ISO_8859_2,
      Encoding::ISO_8859_3,
      Encoding::ISO_8859_4,
      Encoding::ISO_8859_5,
      Encoding::ISO_8859_6,
      Encoding::ISO_8859_7,
      Encoding::ISO_8859_8,
      Encoding::ISO_8859_9,
      Encoding::ISO_8859_10,
      Encoding::ISO_8859_11,
      Encoding::ISO_8859_13,
      Encoding::ISO_8859_14,
      Encoding::ISO_8859_15,
      Encoding::ISO_8859_16,
      Encoding::KOI8_R,
      Encoding::Shift_JIS,
      Encoding::UTF_8,
      Encoding::UTF8_MAC,
      Encoding::Windows_1250,
      Encoding::Windows_1251,
      Encoding::Windows_1252,
      Encoding::Windows_1253,
      Encoding::Windows_1254,
      Encoding::Windows_1255,
      Encoding::Windows_1256,
      Encoding::Windows_1257,
      Encoding::Windows_1258,
      Encoding::Windows_31J
    ].each do |encoding|
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
