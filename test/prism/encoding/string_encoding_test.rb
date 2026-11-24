# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class StringEncodingTest < TestCase
    each_encoding do |encoding|
      define_method(:"test_#{encoding.name}") do
        assert_encoding(encoding)
      end
    end

    def test_coding
      actual = Ruby::Prism.parse_statement("# coding: utf-8\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_coding_with_whitespace
      actual = Ruby::Prism.parse_statement("# coding \t \r  \v   :     \t \v    \r   ascii-8bit \n'string'").unescaped.encoding
      assert_equal Encoding::ASCII_8BIT, actual
    end

    def test_emacs_style
      actual = Ruby::Prism.parse_statement("# -*- coding: utf-8 -*-\n'string'").unescaped.encoding
      assert_equal Encoding::UTF_8, actual
    end

    def test_line_ending_suffixes
      ["UTF-8", "US-ASCII", "BINARY"].each do |name|
        %w[UnIx DoS MaC].each do |suffix|
          ["# coding: #{name}-#{suffix}", "# -*- encoding: #{name}-#{suffix} -*-", "# vim: set fileencoding=#{name}-#{suffix} ts=2"].each do |comment|
            result = Ruby::Prism.parse("#{comment}\n'string'")
            assert_predicate result, :success?, comment
            assert_equal Encoding.find(name), result.statement.unescaped.encoding, comment
          end
        end
      end
    end

    def test_invalid_encoding_suffixes
      %w[UTF-8-* UTF-8garbage UTF-8-garbage UTF-8-DOS-UNIX].each do |name|
        result = Ruby::Prism.parse("# coding: #{name}\n")
        assert_equal [:invalid_encoding_magic_comment], result.errors.map(&:type), name
        assert_equal name, result.errors.first.location.slice
      end
    end

    def test_encoding_comment_with_nul
      ["BINARY\0ignored-unix", "BINARY-unix\0ignored", "UTF-8\0", "\0UTF-8"].each do |name|
        ["# coding: #{name}", "# -*- encoding: \"#{name}\" -*-", "# vim: set fileencoding=#{name} ts=2"].each do |comment|
          result = Ruby::Prism.parse(comment)
          assert_equal [:invalid_encoding_magic_comment], result.errors.map(&:type), comment.inspect
          assert_equal name, result.errors.first.location.slice
        end
      end
    end

    def test_first_lexed_token
      encoding = Ruby::Prism.lex("# encoding: ascii-8bit").value[0].value.encoding
      assert_equal Encoding::ASCII_8BIT, encoding
    end

    # The part of a literal after an interpolation is in the source encoding,
    # whatever encoding the literals inside the interpolation fixed.
    def test_part_after_interpolation
      ['"a#{"\\u3042"}b"', ':"a#{"\\u3042"}b"', '/a#{"\\u3042"}b/'].each do |source|
        node = Ruby::Prism.parse_statement("# encoding: EUC-JP\n#{source}")
        refute_predicate node.parts.last, :forced_utf8_encoding?, source
      end
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_utf8_mac_encoding_names
        %w[uTf8-mAc UTF-8-HFS UTF-8-MAC-DOS].each do |name|
          result = Ruby::Prism.parse("# coding: #{name}\n'string'")
          assert_predicate result, :success?, name
          assert_equal Encoding::UTF8_MAC, result.statement.unescaped.encoding, name
        end

        assert_equal Encoding::UTF8_MAC, Ruby::Prism.parse("", encoding: "UTF-8-MAC").encoding
      end

      # This test may be a little confusing. Basically when we use our strpbrk,
      # it takes into account the encoding of the file.
      def test_strpbrk_multibyte
        result = Ruby::Prism.parse(<<~RUBY)
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
        slice = Ruby::Prism.parse("# encoding: Shift_JIS\nア").value.slice
        assert_equal (+"ア").force_encoding(Encoding::SHIFT_JIS), slice
        assert_equal Encoding::SHIFT_JIS, slice.encoding
      end

      # In CESU-8, a character beyond U+FFFF is a pair of surrogates, and a
      # surrogate on its own is not a character.
      def test_cesu_8_surrogates
        assert Ruby::Prism.parse_success?("# encoding: CESU-8\n\"\xED\xA0\x80\xED\xB0\x80\"")
        assert Ruby::Prism.parse_failure?("# encoding: CESU-8\n\"\xED\xA0\x80\"")
        assert Ruby::Prism.parse_failure?("# encoding: CESU-8\n\"\xED\xB0\x80\"")
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
          assert Ruby::Prism.parse_success?("# encoding: shift_jis\n'\\\x82\xA0'\n")
        end
      end
    end

    def test_encodings_are_not_leaked_across_array_elements
      {
        "[?\\u00E9, ?a, ?\\x61]" => [Encoding::UTF_8, Encoding::ASCII_8BIT, Encoding::ASCII_8BIT],
        "[\"\\u00E9\", ?a]"      => [Encoding::UTF_8, Encoding::ASCII_8BIT],
        "[?\\u00E9, \"a\"]"      => [Encoding::UTF_8, Encoding::ASCII_8BIT],
        "[?\\u00E9, :a]"         => [Encoding::UTF_8, Encoding::US_ASCII],
        "[\"\\u00E9\", :a]"      => [Encoding::UTF_8, Encoding::US_ASCII],
        "[:\"\\u00E9\", :a]"     => [Encoding::UTF_8, Encoding::US_ASCII],
        "[:\"\\u00E9\", :+]"     => [Encoding::UTF_8, Encoding::US_ASCII],
        "%I[\\u00E9 a]"          => [Encoding::UTF_8, Encoding::US_ASCII],
        "%W[\\u00E9 a]"          => [Encoding::UTF_8, Encoding::ASCII_8BIT]
      }.each do |expression, expected|
        result = Ruby::Prism.parse("# encoding: ascii-8bit\n#{expression}")
        assert_predicate result, :success?, "failed to parse: #{expression}"

        actual = result.statement.elements.map { |node| binary_node_encoding(node) }
        assert_equal expected, actual, expression
      end
    end

    def test_encodings_are_not_leaked_across_hash_elements
      {
        "{\"\\u00E9\" => 1, a: 2}" => [Encoding::UTF_8, Encoding::US_ASCII],
        "{\"\\u00E9\": :a}"        => [Encoding::UTF_8],
        "{\"\\u00E9\": ?a}"        => [Encoding::UTF_8],
        "{a: 1, \"\\u00E9\": 2}"   => [Encoding::US_ASCII, Encoding::UTF_8]
      }.each do |expression, expected|
        ["ascii-8bit", "us-ascii"].each do |encoding|
          result = Ruby::Prism.parse("# encoding: #{encoding}\n#{expression}")
          assert_predicate result, :success?, "failed to parse: #{expression}"

          actual = result.statement.elements.map { |assoc| binary_node_encoding(assoc.key) }
          assert_equal expected, actual, "#{encoding} #{expression}"
        end
      end
    end

    def test_invalid_bytes_in_single_quoted_heredocs
      encodings = [Encoding::UTF_8, Encoding::US_ASCII]
      encodings << Encoding::Shift_JIS unless ENV["PRISM_BUILD_MINIMAL"]

      encodings.each do |encoding|
        ["", "-", "~"].each do |indent|
          source = "# encoding: #{encoding.name}\n<<#{indent}'HERE'\n\x81\nHERE\n"
          result = Ruby::Prism.parse(source)

          assert_predicate result, :success?
          assert_equal "\x81\n".b.force_encoding(encoding), result.statement.unescaped
          refute_predicate result.statement.unescaped, :valid_encoding?
        end
      end
    end

    def test_invalid_bytes_in_interpolating_heredocs
      ["HERE", '"HERE"', "`HERE`"].each do |identifier|
        result = Ruby::Prism.parse("# encoding: UTF-8\n<<#{identifier}\n\x81\nHERE\n")
        assert_equal [:invalid_multibyte_character], result.errors.map(&:type)
      end
    end

    def test_invalid_bytes_after_single_quoted_heredoc_breakpoints
      ["a\n\x81\n", "a\r\n\x81\n", "\0\x81\n", "\\a\x81\n", "\\\x81\n", "\#{x}\x81\n"].each do |body|
        result = Ruby::Prism.parse("# encoding: UTF-8\n<<'HERE'\n#{body}HERE\n")
        assert_predicate result, :success?, body.inspect
        assert_equal body.b.gsub("\r\n", "\n").force_encoding(body.encoding), result.statement.unescaped
      end
    end

    private

    def binary_node_encoding(node)
      case node
      when StringNode
        node.forced_utf8_encoding? ? Encoding::UTF_8 : Encoding::ASCII_8BIT
      when SymbolNode
        if node.forced_utf8_encoding?
          Encoding::UTF_8
        elsif node.forced_binary_encoding?
          Encoding::ASCII_8BIT
        elsif node.forced_us_ascii_encoding?
          Encoding::US_ASCII
        else
          Encoding::ASCII_8BIT
        end
      else
        flunk "unexpected node type: #{node.class}"
      end
    end

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
          Ruby::Prism.parse(source).then do |result|
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
