# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "../test_helper"

module Prism
  class SymbolEncodingTest < TestCase
    each_encoding do |encoding, _|
      define_method(:"test_symbols_#{encoding.name}") do
        assert_symbols(encoding)
      end

      define_method(:"test_escapes_#{encoding.name}") do
        assert_escapes(encoding)
      end
    end

    private

    def expected_encoding(source)
      eval(source).encoding
    end

    def actual_encoding(source, encoding)
      result = Prism.parse(source)

      if result.success?
        symbol = result.statement

        if symbol.forced_utf8_encoding?
          Encoding::UTF_8
        elsif symbol.forced_binary_encoding?
          Encoding::ASCII_8BIT
        elsif symbol.forced_us_ascii_encoding?
          Encoding::US_ASCII
        else
          encoding
        end
      else
        raise SyntaxError.new(result.errors.map(&:message).join("\n"))
      end
    end

    def assert_symbols(encoding)
      [:a, :ą, :+].each do |symbol|
        source = "# encoding: #{encoding.name}\n#{symbol.inspect}"

        expected =
          begin
            expected_encoding(source)
          rescue SyntaxError => error
            if error.message.include?("invalid multibyte")
              "invalid multibyte"
            else
              raise
            end
          end

        actual =
          begin
            actual_encoding(source, encoding)
          rescue SyntaxError => error
            if error.message.include?("invalid multibyte")
              "invalid multibyte"
            else
              raise
            end
          end

        assert_equal expected, actual
      end
    end

    def assert_escapes(encoding)
      escapes = ["\\x00", "\\x7F", "\\x80", "\\xFF", "\\u{00}", "\\u{7F}", "\\u{80}", "\\M-\\C-?"]
      escapes = escapes.concat(escapes.product(escapes).map(&:join))

      escapes.each do |escaped|
        source = "# encoding: #{encoding.name}\n:\"#{escaped}\""

        expected =
          begin
            expected_encoding(source)
          rescue SyntaxError => error
            if error.message.include?("UTF-8 mixed within")
              error.message[/UTF-8 mixed within .+? source/]
            else
              raise
            end
          end

        actual =
          begin
            actual_encoding(source, encoding)
          rescue SyntaxError => error
            if error.message.include?("mixed")
              error.message.split("\n", 2).first
            else
              raise
            end
          end

        assert_equal expected, actual
      end
    end
  end
end
