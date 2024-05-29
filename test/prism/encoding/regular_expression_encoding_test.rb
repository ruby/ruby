# frozen_string_literal: true

return unless defined?(RubyVM::InstructionSequence)
return if RubyVM::InstructionSequence.compile("").to_a[4][:parser] == :prism

require_relative "../test_helper"

module Prism
  class RegularExpressionEncodingTest < TestCase
    each_encoding do |encoding, _|
      define_method(:"test_regular_expression_encoding_flags_#{encoding.name}") do
        assert_regular_expression_encoding_flags(encoding, ["/a/", "/ą/", "//"])
      end

      escapes = ["\\x00", "\\x7F", "\\x80", "\\xFF", "\\u{00}", "\\u{7F}", "\\u{80}", "\\M-\\C-?"]
      escapes = escapes.concat(escapes.product(escapes).map(&:join))

      define_method(:"test_regular_expression_escape_encoding_flags_#{encoding.name}") do
        assert_regular_expression_encoding_flags(encoding, escapes.map { |e| "/#{e}/" })
      end

      ["n", "u", "e", "s"].each do |modifier|
        define_method(:"test_regular_expression_encoding_modifiers_/#{modifier}_#{encoding.name}") do
          regexp_sources = ["abc", "garçon", "\\x80", "gar\\xC3\\xA7on", "gar\\u{E7}on", "abc\\u{FFFFFF}", "\\x80\\u{80}" ]

          assert_regular_expression_encoding_flags(
            encoding,
            regexp_sources.product(["n", "u", "e", "s"]).map { |r, modifier| "/#{r}/#{modifier}" }
          )
        end
      end
    end

    private

    def assert_regular_expression_encoding_flags(encoding, regexps)
      regexps.each do |regexp|
        regexp_modifier_used = regexp.end_with?("/u") || regexp.end_with?("/e") || regexp.end_with?("/s") || regexp.end_with?("/n")
        source = "# encoding: #{encoding.name}\n#{regexp}"

        encoding_errors = ["invalid multibyte char", "escaped non ASCII character in UTF-8 regexp", "differs from source encoding"]
        skipped_errors = ["invalid multibyte escape", "incompatible character encoding", "UTF-8 character in non UTF-8 regexp", "invalid Unicode range", "invalid Unicode list"]

        # TODO (nirvdrum 21-Feb-2024): Prism currently does not handle Regexp validation unless modifiers are used. So, skip processing those errors for now: https://github.com/ruby/prism/issues/2104
        unless regexp_modifier_used
          skipped_errors += encoding_errors
          encoding_errors.clear
        end

        expected =
          begin
            eval(source).encoding
          rescue SyntaxError => error
            if encoding_errors.find { |e| error.message.include?(e) }
              error.message.split("\n").map { |m| m[/: (.+?)$/, 1] }
            elsif skipped_errors.find { |e| error.message.include?(e) }
              next
            else
              raise
            end
          end

        actual =
          Prism.parse(source).then do |result|
            if result.success?
              regexp = result.statement

              actual_encoding = if regexp.forced_utf8_encoding?
                Encoding::UTF_8
              elsif regexp.forced_binary_encoding?
                Encoding::ASCII_8BIT
              elsif regexp.forced_us_ascii_encoding?
                Encoding::US_ASCII
              elsif regexp.ascii_8bit?
                Encoding::ASCII_8BIT
              elsif regexp.utf_8?
                Encoding::UTF_8
              elsif regexp.euc_jp?
                Encoding::EUC_JP
              elsif regexp.windows_31j?
                Encoding::Windows_31J
              else
                encoding
              end

              if regexp.utf_8? && actual_encoding != Encoding::UTF_8
                raise "expected regexp encoding to be UTF-8 due to '/u' modifier, but got #{actual_encoding.name}"
              elsif regexp.ascii_8bit? && (actual_encoding != Encoding::ASCII_8BIT && actual_encoding != Encoding::US_ASCII)
                raise "expected regexp encoding to be ASCII-8BIT or US-ASCII due to '/n' modifier, but got #{actual_encoding.name}"
              elsif regexp.euc_jp? && actual_encoding != Encoding::EUC_JP
                raise "expected regexp encoding to be EUC-JP due to '/e' modifier, but got #{actual_encoding.name}"
              elsif regexp.windows_31j? && actual_encoding != Encoding::Windows_31J
                raise "expected regexp encoding to be Windows-31J due to '/s' modifier, but got #{actual_encoding.name}"
              end

              if regexp.utf_8? && regexp.forced_utf8_encoding?
                raise "the forced_utf8 flag should not be set when the UTF-8 modifier (/u) is used"
              elsif regexp.ascii_8bit? && regexp.forced_binary_encoding?
                raise "the forced_ascii_8bit flag should not be set when the UTF-8 modifier (/u) is used"
              end

              actual_encoding
            else
              errors = result.errors.map(&:message)

              if errors.last&.include?("UTF-8 mixed within")
                nil
              else
                errors
              end
            end
          end

        # TODO (nirvdrum 22-Feb-2024): Remove this workaround once Prism better maps CRuby's error messages.
        # This class of error message is tricky. The part not being compared is a representation of the regexp.
        # Depending on the source encoding and any encoding modifiers being used, CRuby alters how the regexp is represented.
        # Sometimes it's an MBC string. Other times it uses hexadecimal character escapes. And in other cases it uses
        # the long-form Unicode escape sequences. This short-circuit checks that the error message is mostly correct.
        if expected.is_a?(Array) && actual.is_a?(Array)
          if expected.last.start_with?("/.../n has a non escaped non ASCII character in non ASCII-8BIT script:") &&
              actual.last.start_with?("/.../n has a non escaped non ASCII character in non ASCII-8BIT script:")
              expected.last.clear
              actual.last.clear
          end
        end

        assert_equal expected, actual
      end
    end
  end
end
