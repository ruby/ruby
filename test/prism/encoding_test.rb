# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "test_helper"

module Prism
  class EncodingTest < TestCase
    encodings = {
      Encoding::ASCII =>        0x00...0x100,
      Encoding::ASCII_8BIT =>   0x00...0x100,
      Encoding::CP850 =>        0x00...0x100,
      Encoding::CP852 =>        0x00...0x100,
      Encoding::CP855 =>        0x00...0x100,
      Encoding::GB1988 =>       0x00...0x100,
      Encoding::IBM437 =>       0x00...0x100,
      Encoding::IBM720 =>       0x00...0x100,
      Encoding::IBM737 =>       0x00...0x100,
      Encoding::IBM775 =>       0x00...0x100,
      Encoding::IBM852 =>       0x00...0x100,
      Encoding::IBM855 =>       0x00...0x100,
      Encoding::IBM857 =>       0x00...0x100,
      Encoding::IBM860 =>       0x00...0x100,
      Encoding::IBM861 =>       0x00...0x100,
      Encoding::IBM862 =>       0x00...0x100,
      Encoding::IBM863 =>       0x00...0x100,
      Encoding::IBM864 =>       0x00...0x100,
      Encoding::IBM865 =>       0x00...0x100,
      Encoding::IBM866 =>       0x00...0x100,
      Encoding::IBM869 =>       0x00...0x100,
      Encoding::ISO_8859_1 =>   0x00...0x100,
      Encoding::ISO_8859_2 =>   0x00...0x100,
      Encoding::ISO_8859_3 =>   0x00...0x100,
      Encoding::ISO_8859_4 =>   0x00...0x100,
      Encoding::ISO_8859_5 =>   0x00...0x100,
      Encoding::ISO_8859_6 =>   0x00...0x100,
      Encoding::ISO_8859_7 =>   0x00...0x100,
      Encoding::ISO_8859_8 =>   0x00...0x100,
      Encoding::ISO_8859_9 =>   0x00...0x100,
      Encoding::ISO_8859_10 =>  0x00...0x100,
      Encoding::ISO_8859_11 =>  0x00...0x100,
      Encoding::ISO_8859_13 =>  0x00...0x100,
      Encoding::ISO_8859_14 =>  0x00...0x100,
      Encoding::ISO_8859_15 =>  0x00...0x100,
      Encoding::ISO_8859_16 =>  0x00...0x100,
      Encoding::KOI8_R =>       0x00...0x100,
      Encoding::KOI8_U =>       0x00...0x100,
      Encoding::MACCENTEURO =>  0x00...0x100,
      Encoding::MACCROATIAN =>  0x00...0x100,
      Encoding::MACCYRILLIC =>  0x00...0x100,
      Encoding::MACGREEK =>     0x00...0x100,
      Encoding::MACICELAND =>   0x00...0x100,
      Encoding::MACROMAN =>     0x00...0x100,
      Encoding::MACROMANIA =>   0x00...0x100,
      Encoding::MACTHAI =>      0x00...0x100,
      Encoding::MACTURKISH =>   0x00...0x100,
      Encoding::TIS_620 =>      0x00...0x100,
      Encoding::Windows_1250 => 0x00...0x100,
      Encoding::Windows_1251 => 0x00...0x100,
      Encoding::Windows_1252 => 0x00...0x100,
      Encoding::Windows_1253 => 0x00...0x100,
      Encoding::Windows_1254 => 0x00...0x100,
      Encoding::Windows_1255 => 0x00...0x100,
      Encoding::Windows_1256 => 0x00...0x100,
      Encoding::Windows_1257 => 0x00...0x100,
      Encoding::Windows_1258 => 0x00...0x100,
      Encoding::Windows_874 =>  0x00...0x100,
      Encoding::Big5 =>         0x00...0x10000,
      Encoding::Big5_HKSCS =>   0x00...0x10000,
      Encoding::Big5_UAO =>     0x00...0x10000,
      Encoding::CP949 =>        0x00...0x10000,
      Encoding::CP51932 =>      0x00...0x10000,
      Encoding::GBK =>          0x00...0x10000,
      Encoding::Shift_JIS =>    0x00...0x10000,
      Encoding::Windows_31J =>  0x00...0x10000
    }

    # By default we don't test every codepoint in these encodings because they
    # are 3 and 4 byte representations so it can drastically slow down the test
    # suite.
    if ENV["PRISM_TEST_ALL_ENCODINGS"]
      encodings.merge!(
        Encoding::EUC_JP =>   0x00...0x1000000,
        Encoding::UTF_8 =>    0x00...0x110000,
        Encoding::UTF8_MAC => 0x00...0x110000
      )
    end

    encodings.each do |encoding, range|
      encoding.names.each do |name|
        next if name == "locale"

        define_method(:"test_encoding_#{name}") do
          assert_encoding(encoding, name, range)
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

    private

    class ConstantContext < BasicObject
      def self.const_missing(const)
        const
      end
    end

    def constant_context
      ConstantContext.new
    end

    class IdentifierContext < BasicObject
      def method_missing(name, *)
        name
      end
    end

    def identifier_context
      IdentifierContext.new
    end

    def assert_encoding_constant(name, character)
      source = "# encoding: #{name}\n#{character}"
      expected = constant_context.instance_eval(source)

      result = Prism.parse(source)
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of ConstantReadNode, actual
      assert_equal expected, actual.name
    end

    def assert_encoding_identifier(name, character)
      source = "# encoding: #{name}\n#{character}"
      expected = identifier_context.instance_eval(source)

      result = Prism.parse(source)
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of CallNode, actual
      assert_equal expected, actual.name
    end

    # Check that we can properly parse every codepoint in the given encoding.
    def assert_encoding(encoding, name, range)
      # I'm not entirely sure, but I believe these codepoints are incorrect in
      # their parsing in CRuby. They all report as matching `[[:lower:]]` but
      # then they are parsed as constants. This is because CRuby determines if
      # an identifier is a constant or not by case folding it down to lowercase
      # and checking if there is a difference. And even though they report
      # themselves as lowercase, their case fold is different. I have reported
      # this bug upstream.
      case encoding
      when Encoding::UTF_8, Encoding::UTF_8_MAC
        range = range.to_a - [
          0x01c5, 0x01c8, 0x01cb, 0x01f2, 0x1f88, 0x1f89, 0x1f8a, 0x1f8b,
          0x1f8c, 0x1f8d, 0x1f8e, 0x1f8f, 0x1f98, 0x1f99, 0x1f9a, 0x1f9b,
          0x1f9c, 0x1f9d, 0x1f9e, 0x1f9f, 0x1fa8, 0x1fa9, 0x1faa, 0x1fab,
          0x1fac, 0x1fad, 0x1fae, 0x1faf, 0x1fbc, 0x1fcc, 0x1ffc,
        ]
      when Encoding::Windows_1253
        range = range.to_a - [0xb5]
      end

      range.each do |codepoint|
        character = codepoint.chr(encoding)

        if character.match?(/[[:alpha:]]/)
          if character.match?(/[[:upper:]]/)
            assert_encoding_constant(name, character)
          else
            assert_encoding_identifier(name, character)
          end
        elsif character.match?(/[[:alnum:]]/)
          assert_encoding_identifier(name, "_#{character}")
        else
          next if ["/", "{"].include?(character)

          source = "# encoding: #{name}\n/(?##{character})/\n"
          assert Prism.parse(source).success?
        end
      rescue RangeError
        source = "# encoding: #{name}\n\\x#{codepoint.to_s(16)}"
        refute Prism.parse(source).success?
      end
    end
  end
end
