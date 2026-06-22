# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "../test_helper"

module Prism
  class EncodingsTest < TestCase
    class ConstantContext < BasicObject
      def self.const_missing(const)
        const
      end
    end

    class IdentifierContext < BasicObject
      def method_missing(name, *)
        name
      end
    end

    # These test that we're correctly parsing codepoints for each alias of each
    # encoding that prism supports.
    each_encoding do |encoding, range|
      (encoding.names - %w[external internal filesystem locale]).each do |name|
        define_method(:"test_encoding_#{name}") do
          assert_encoding(encoding, name, range)
        end
      end
    end

    private

    def assert_encoding_constant(name, character)
      source = "# encoding: #{name}\n#{character}"
      expected = ConstantContext.new.instance_eval(source)

      result = Prism.parse(source)
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of ConstantReadNode, actual
      assert_equal expected, actual.name
    end

    def assert_encoding_identifier(name, character)
      source = "# encoding: #{name}\n#{character}"
      expected = IdentifierContext.new.instance_eval(source)

      result = Prism.parse(source)
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of CallNode, actual
      assert_equal expected, actual.name
    end

    # Check that we can properly parse every codepoint in the given encoding.
    def assert_encoding(encoding, name, range)
      unicode = false

      case encoding
      when Encoding::UTF_8, Encoding::UTF_8_MAC, Encoding::UTF8_DoCoMo, Encoding::UTF8_KDDI, Encoding::UTF8_SoftBank, Encoding::CESU_8
        unicode = true
      when Encoding::Windows_1253
        range = range.to_a - [0xb5]
      end

      range.each do |codepoint|
        character = codepoint.chr(encoding)

        if character.match?(/[[:alpha:]]/)
          if character.match?(/[[:upper:]]/) || (unicode && character.match?(Regexp.new("\\p{Lt}".encode(encoding))))
            assert_encoding_constant(name, character)
          else
            assert_encoding_identifier(name, character)
          end
        elsif character.match?(/[[:alnum:]]/)
          assert_encoding_identifier(name, "_#{character}")
        else
          next if ["/", "{"].include?(character)

          source = "# encoding: #{name}\n/(?##{character})/\n"
          assert Prism.parse_success?(source), "Expected #{source.inspect} to parse successfully."
        end
      rescue RangeError
        source = "# encoding: #{name}\n\\x#{codepoint.to_s(16)}"
        assert Prism.parse_failure?(source)
      end
    end
  end
end
