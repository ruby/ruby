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
          assert Prism.parse_success?(source), "Expected #{source.inspect} to parse successfully."
        end
      rescue RangeError
        source = "# encoding: #{name}\n\\x#{codepoint.to_s(16)}"
        assert Prism.parse_failure?(source)
      end
    end
  end
end
