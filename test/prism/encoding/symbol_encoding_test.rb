# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "../test_helper"

module Ruby::Prism
  class SymbolEncodingTest < TestCase
    each_encoding do |encoding|
      define_method(:"test_symbols_#{encoding.name}") do
        assert_symbols(encoding)
      end

      define_method(:"test_escapes_#{encoding.name}") do
        assert_escapes(encoding)
      end
    end

    def test_invalid_static_symbol_array_elements
      ["%I[\\xC0]", "%I[valid \\xC0]", "%I[\\xC0 valid]", "%I[\\xC0\\xAF]"].each do |expression|
        source = "# encoding: UTF-8\nif false\n#{expression}\nend"
        result = Ruby::Prism.parse(source)

        assert_equal [:invalid_symbol], result.errors.map(&:type), expression
        assert_match(/\\xC0/, result.errors.first.location.slice)
      end
    end

    def test_invalid_bytes_in_dynamic_symbol_array_elements
      ['%I[\xC0#{x}]', '%I[#{x}\xC0]'].each do |expression|
        assert_predicate Ruby::Prism.parse("# encoding: UTF-8\n#{expression}"), :success?
      end
    end

    def test_symbol_array_element_encodings
      ["binary", "us-ascii"].each do |encoding|
        result = Ruby::Prism.parse("# encoding: #{encoding}\n%I[\\xC0 \\u3042 ascii]")
        assert_predicate result, :success?
        binary, utf8, ascii = result.statement.elements
        assert_equal [0xC0], binary.unescaped.bytes
        assert_equal encoding == "us-ascii", binary.forced_binary_encoding?
        assert_predicate utf8, :forced_utf8_encoding?
        assert_predicate ascii, :forced_us_ascii_encoding?
      end
    end

    private

    def expected_encoding(source)
      eval(source).encoding
    end

    def actual_encoding(source, encoding)
      result = Ruby::Prism.parse(source)

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
            elsif error.message.include?("invalid symbol")
              "invalid symbol"
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
            elsif error.message.include?("invalid symbol")
              "invalid symbol"
            else
              raise
            end
          end

        assert_equal expected, actual
      end
    end
  end
end
