# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class StringEncodingTest < TestCase
    each_encoding do |encoding, _|
      define_method(:"test_#{encoding.name}") do
        assert_encoding(encoding)
      end
    end

    def test_coding
      actual = Prism.parse_statement("# coding: utf-8\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_coding_with_whitespace
      actual = Prism.parse_statement("# coding \t \r  \v   :     \t \v    \r   ascii-8bit \n'string'").unescaped.encoding
      assert_equal Encoding::ASCII_8BIT, actual
    end

    def test_emacs_style
      actual = Prism.parse_statement("# -*- coding: utf-8 -*-\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_utf_8_unix
      actual = Prism.parse_statement("# coding: utf-8-unix\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_utf_8_dos
      actual = Prism.parse_statement("# coding: utf-8-dos\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_utf_8_mac
      actual = Prism.parse_statement("# coding: utf-8-mac\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_utf_8_star
      actual = Prism.parse_statement("# coding: utf-8-*\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_first_lexed_token
      encoding = Prism.lex("# encoding: ascii-8bit").value[0][0].value.encoding
      assert_equal Encoding::ASCII_8BIT, encoding
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      # This test may be a little confusing. Basically when we use our strpbrk,
      # it takes into account the encoding of the file.
      def test_strpbrk_multibyte
        result = Prism.parse(<<~RUBY)
          # encoding: Shift_JIS
          %w[\x81\x5c]
        RUBY

        assert(result.errors.empty?)
        assert_equal(
          (+"\x81\x5c").force_encoding(Encoding::Shift_JIS),
          result.statement.elements.first.unescaped
        )
      end

      def test_slice_encoding
        slice = Prism.parse("# encoding: Shift_JIS\nア").value.slice
        assert_equal (+"ア").force_encoding(Encoding::SHIFT_JIS), slice
        assert_equal Encoding::SHIFT_JIS, slice.encoding
      end

      def test_multibyte_escapes
        [
          ["'", "'"],
          ["\"", "\""],
          ["`", "`"],
          ["/", "/"],
          ["<<'HERE'\n", "\nHERE"],
          ["<<-HERE\n", "\nHERE"]
        ].each do |opening, closing|
          assert Prism.parse_success?("# encoding: shift_jis\n'\\\x82\xA0'\n")
        end
      end
    end

    private

    def assert_encoding(encoding)
      escapes = ["\\x00", "\\x7F", "\\x80", "\\xFF", "\\u{00}", "\\u{7F}", "\\u{80}", "\\M-\\C-?"]
      escapes = escapes.concat(escapes.product(escapes).map(&:join))

      escapes.each do |escaped|
        source = "# encoding: #{encoding.name}\n\"#{escaped}\""

        expected =
          begin
            eval(source).encoding
          rescue SyntaxError => error
            if error.message.include?("UTF-8 mixed within")
              error.message[/UTF-8 mixed within .+? source/]
            else
              raise
            end
          end

        actual =
          Prism.parse(source).then do |result|
            if result.success?
              string = result.statement

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
