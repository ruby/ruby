# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class EncodingTest < TestCase
    %w[
      ascii
      ascii-8bit
      big5
      binary
      euc-jp
      gbk
      iso-8859-1
      iso-8859-2
      iso-8859-3
      iso-8859-4
      iso-8859-5
      iso-8859-6
      iso-8859-7
      iso-8859-8
      iso-8859-9
      iso-8859-10
      iso-8859-11
      iso-8859-13
      iso-8859-14
      iso-8859-15
      iso-8859-16
      koi8-r
      shift_jis
      sjis
      us-ascii
      utf-8
      utf8-mac
      windows-31j
      windows-1251
      windows-1252
      CP1251
      CP1252
    ].each do |encoding|
      define_method "test_encoding_#{encoding}" do
        result = Prism.parse("# encoding: #{encoding}\n'string'")
        actual = result.value.statements.body.first.unescaped.encoding
        assert_equal Encoding.find(encoding), actual
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
