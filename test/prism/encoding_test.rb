# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "test_helper"

module Prism
  class EncodingTest < TestCase
    codepoints_1byte = 0...0x100
    encodings = {
      Encoding::ASCII_8BIT =>   codepoints_1byte,
      Encoding::US_ASCII =>     codepoints_1byte,
      Encoding::Windows_1253 => codepoints_1byte
    }

    # By default we don't test every codepoint in these encodings because it
    # takes a very long time.
    if ENV["PRISM_TEST_ALL_ENCODINGS"]
      codepoints_2bytes = 0...0x10000
      codepoints_unicode = (0...0x110000)

      codepoints_eucjp = [
        *(0...0x10000),
        *(0...0x10000).map { |bytes| bytes | 0x8F0000 }
      ]

      codepoints_emacs_mule = [
        *(0...0x80),
        *((0x81...0x90).flat_map { |byte1| (0x90...0x100).map { |byte2| byte1 << 8 | byte2 } }),
        *((0x90...0x9C).flat_map { |byte1| (0xA0...0x100).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| byte1 << 16 | byte2 << 8 | byte3 } } }),
        *((0xF0...0xF5).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| (0xA0...0x100).flat_map { |byte4| 0x9C << 24 | byte3 << 16 | byte3 << 8 | byte4 } } }),
      ]

      codepoints_gb18030 = [
        *(0...0x80),
        *((0x81..0xFE).flat_map { |byte1| (0x40...0x100).map { |byte2| byte1 << 8 | byte2 } }),
        *((0x81..0xFE).flat_map { |byte1| (0x30...0x40).flat_map { |byte2| (0x81..0xFE).flat_map { |byte3| (0x2F...0x41).map { |byte4| byte1 << 24 | byte2 << 16 | byte3 << 8 | byte4 } } } }),
      ]

      codepoints_euc_tw = [
        *(0..0x7F),
        *(0xA1..0xFF).flat_map { |byte1| (0xA1..0xFF).map { |byte2| (byte1 << 8) | byte2 } },
        *(0xA1..0xB0).flat_map { |byte2| (0xA1..0xFF).flat_map { |byte3| (0xA1..0xFF).flat_map { |byte4| 0x8E << 24 | byte2 << 16 | byte3 << 8 | byte4 } } }
      ]

      encodings.merge!(
        Encoding::CP850 =>                      codepoints_1byte,
        Encoding::CP852 =>                      codepoints_1byte,
        Encoding::CP855 =>                      codepoints_1byte,
        Encoding::GB1988 =>                     codepoints_1byte,
        Encoding::IBM437 =>                     codepoints_1byte,
        Encoding::IBM720 =>                     codepoints_1byte,
        Encoding::IBM737 =>                     codepoints_1byte,
        Encoding::IBM775 =>                     codepoints_1byte,
        Encoding::IBM852 =>                     codepoints_1byte,
        Encoding::IBM855 =>                     codepoints_1byte,
        Encoding::IBM857 =>                     codepoints_1byte,
        Encoding::IBM860 =>                     codepoints_1byte,
        Encoding::IBM861 =>                     codepoints_1byte,
        Encoding::IBM862 =>                     codepoints_1byte,
        Encoding::IBM863 =>                     codepoints_1byte,
        Encoding::IBM864 =>                     codepoints_1byte,
        Encoding::IBM865 =>                     codepoints_1byte,
        Encoding::IBM866 =>                     codepoints_1byte,
        Encoding::IBM869 =>                     codepoints_1byte,
        Encoding::ISO_8859_1 =>                 codepoints_1byte,
        Encoding::ISO_8859_2 =>                 codepoints_1byte,
        Encoding::ISO_8859_3 =>                 codepoints_1byte,
        Encoding::ISO_8859_4 =>                 codepoints_1byte,
        Encoding::ISO_8859_5 =>                 codepoints_1byte,
        Encoding::ISO_8859_6 =>                 codepoints_1byte,
        Encoding::ISO_8859_7 =>                 codepoints_1byte,
        Encoding::ISO_8859_8 =>                 codepoints_1byte,
        Encoding::ISO_8859_9 =>                 codepoints_1byte,
        Encoding::ISO_8859_10 =>                codepoints_1byte,
        Encoding::ISO_8859_11 =>                codepoints_1byte,
        Encoding::ISO_8859_13 =>                codepoints_1byte,
        Encoding::ISO_8859_14 =>                codepoints_1byte,
        Encoding::ISO_8859_15 =>                codepoints_1byte,
        Encoding::ISO_8859_16 =>                codepoints_1byte,
        Encoding::KOI8_R =>                     codepoints_1byte,
        Encoding::KOI8_U =>                     codepoints_1byte,
        Encoding::MACCENTEURO =>                codepoints_1byte,
        Encoding::MACCROATIAN =>                codepoints_1byte,
        Encoding::MACCYRILLIC =>                codepoints_1byte,
        Encoding::MACGREEK =>                   codepoints_1byte,
        Encoding::MACICELAND =>                 codepoints_1byte,
        Encoding::MACROMAN =>                   codepoints_1byte,
        Encoding::MACROMANIA =>                 codepoints_1byte,
        Encoding::MACTHAI =>                    codepoints_1byte,
        Encoding::MACTURKISH =>                 codepoints_1byte,
        Encoding::MACUKRAINE =>                 codepoints_1byte,
        Encoding::TIS_620 =>                    codepoints_1byte,
        Encoding::Windows_1250 =>               codepoints_1byte,
        Encoding::Windows_1251 =>               codepoints_1byte,
        Encoding::Windows_1252 =>               codepoints_1byte,
        Encoding::Windows_1254 =>               codepoints_1byte,
        Encoding::Windows_1255 =>               codepoints_1byte,
        Encoding::Windows_1256 =>               codepoints_1byte,
        Encoding::Windows_1257 =>               codepoints_1byte,
        Encoding::Windows_1258 =>               codepoints_1byte,
        Encoding::Windows_874 =>                codepoints_1byte,
        Encoding::Big5 =>                       codepoints_2bytes,
        Encoding::Big5_HKSCS =>                 codepoints_2bytes,
        Encoding::Big5_UAO =>                   codepoints_2bytes,
        Encoding::CP949 =>                      codepoints_2bytes,
        Encoding::CP950 =>                      codepoints_2bytes,
        Encoding::CP951 =>                      codepoints_2bytes,
        Encoding::EUC_KR =>                     codepoints_2bytes,
        Encoding::GBK =>                        codepoints_2bytes,
        Encoding::GB12345 =>                    codepoints_2bytes,
        Encoding::GB2312 =>                     codepoints_2bytes,
        Encoding::MACJAPANESE =>                codepoints_2bytes,
        Encoding::Shift_JIS =>                  codepoints_2bytes,
        Encoding::SJIS_DoCoMo =>                codepoints_2bytes,
        Encoding::SJIS_KDDI =>                  codepoints_2bytes,
        Encoding::SJIS_SoftBank =>              codepoints_2bytes,
        Encoding::Windows_31J =>                codepoints_2bytes,
        Encoding::UTF_8 =>                      codepoints_unicode,
        Encoding::UTF8_MAC =>                   codepoints_unicode,
        Encoding::UTF8_DoCoMo =>                codepoints_unicode,
        Encoding::UTF8_KDDI =>                  codepoints_unicode,
        Encoding::UTF8_SoftBank =>              codepoints_unicode,
        Encoding::CESU_8 =>                     codepoints_unicode,
        Encoding::CP51932 =>                    codepoints_eucjp,
        Encoding::EUC_JP =>                     codepoints_eucjp,
        Encoding::EUCJP_MS =>                   codepoints_eucjp,
        Encoding::EUC_JIS_2004 =>               codepoints_eucjp,
        Encoding::EMACS_MULE =>                 codepoints_emacs_mule,
        Encoding::STATELESS_ISO_2022_JP =>      codepoints_emacs_mule,
        Encoding::STATELESS_ISO_2022_JP_KDDI => codepoints_emacs_mule,
        Encoding::GB18030 =>                    codepoints_gb18030,
        Encoding::EUC_TW =>                     codepoints_euc_tw
      )
    end

    # These test that we're correctly parsing codepoints for each alias of each
    # encoding that prism supports.
    encodings.each do |encoding, range|
      encoding.names.each do |name|
        next if name == "locale"

        define_method(:"test_encoding_#{name}") do
          assert_encoding(encoding, name, range)
        end
      end
    end

    # These test that we're correctly setting the flags on strings for each
    # encoding that prism supports.
    escapes = ["\\x00", "\\x7F", "\\x80", "\\xFF", "\\u{00}", "\\u{7F}", "\\u{80}", "\\M-\\C-?"]
    escapes = escapes.concat(escapes.product(escapes).map(&:join))

    encodings.each_key do |encoding|
      define_method(:"test_encoding_flags_#{encoding.name}") do
        assert_encoding_flags(encoding, escapes)
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
      when Encoding::UTF_8, Encoding::UTF_8_MAC, Encoding::UTF8_DoCoMo, Encoding::UTF8_KDDI, Encoding::UTF8_SoftBank, Encoding::CESU_8
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

    def assert_encoding_flags(encoding, escapes)
      escapes.each do |escaped|
        source = "# encoding: #{encoding.name}\n\"#{escaped}\""

        expected =
          begin
            eval(source).encoding
          rescue SyntaxError => error
            if error.message.include?("UTF-8 mixed within")
              error.message[/: (.+?)\n/, 1]
            else
              raise
            end
          end

        actual =
          Prism.parse(source).then do |result|
            if result.success?
              string = result.value.statements.body.first

              if string.forced_utf8_encoding?
                Encoding::UTF_8
              elsif string.forced_binary_encoding?
                Encoding::ASCII_8BIT
              else
                encoding
              end
            else
              error = result.errors.first

              if error.message.include?("mixed")
                error.message
              else
                raise error.message
              end
            end
          end

        assert_equal expected, actual
      end
    end
  end
end
