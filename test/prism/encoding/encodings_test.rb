# frozen_string_literal: true

return if RUBY_ENGINE != "ruby"

require_relative "../test_helper"

module Ruby::Prism
  class EncodingsTest < TestCase
    # Emacs-Mule, and the encodings that share its characters.
    EMACS_MULE_ENCODINGS = [Encoding::Emacs_Mule, Encoding::Stateless_ISO_2022_JP, Encoding::Stateless_ISO_2022_JP_KDDI]

    # These test that we're correctly parsing codepoints for each alias of each
    # encoding that prism supports.
    each_encoding do |encoding, range|
      (encoding.names - %w[external internal filesystem locale]).each do |name|
        define_method(:"test_encoding_#{name}") do
          assert_encoding(encoding, name, range)
        end
      end
    end

    # Every encoding that prism supports is ASCII-compatible, so identifiers made
    # of ASCII characters lex the same in all of them.
    each_encoding do |encoding, _|
      define_method(:"test_ascii_identifiers_#{encoding.name}") do
        assert_ascii_identifiers(encoding)
      end
    end

    # In an encoding that is not Unicode, a character that is neither uppercase
    # nor lowercase begins a constant if case folding changes it. Windows-1252
    # folds the multiplication sign to the division sign, for example.
    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_case_folded_constants
        { "ISO-8859-16" => [0xA4], "Windows-1250" => [0xD7], "Windows-1252" => [0xAF, 0xD7] }.each do |name, bytes|
          bytes.each do |byte|
            character = byte.chr(Encoding.find(name))
            assert constant_start?(character), "Expected Ruby to read #{character.inspect} in #{name} as a constant."
            assert_encoding_constant(name, character)
          end
        end
      end

      # In Emacs-Mule, and the encodings that share its characters, no character
      # that is not ASCII is uppercase, so a name that starts with one is a
      # local name.
      def test_emacs_mule_locals
        EMACS_MULE_ENCODINGS.each do |encoding|
          [0x81A0, 0x90A0A0, 0x9AE0A0, 0x9CF0A0A0, 0x9DF5A0A0].each do |codepoint|
            assert_encoding_identifier(encoding.name, codepoint.chr(encoding))
          end
        end
      end
    end

    private

    # Return true if a name that starts with the character is a constant name.
    # Object.const_defined? raises a NameError for a name that is not one.
    #
    # Ruby before 4.1 reads every character of Emacs-Mule that is not ASCII as
    # uppercase, because of a bug in the character types of the encoding (Bug
    # #22491). Ruby::Prism reads those characters as Ruby 4.1 does, as the start of a
    # local name.
    def constant_start?(character)
      return false if EMACS_MULE_ENCODINGS.include?(character.encoding) && !character.ascii_only?

      Object.const_defined?(character)
      true
    rescue NameError
      false
    end

    # Return the symbol that a name made of the given characters is in a source
    # file with the given encoding magic comment. A name like UTF-8-MAC ends in
    # an Emacs line ending, so Ruby reads the source as UTF-8 rather than
    # UTF8-MAC.
    def expected_name(name, characters)
      encoding = eval("# encoding: #{name}\n__ENCODING__")
      characters.b.force_encoding(encoding).to_sym
    end

    # These identifiers are longer than the bytes that the lexer scans at once
    # for ASCII identifier characters.
    def assert_ascii_identifiers(encoding)
      local = "abcdefghijklmnopqrstuvwxyz_0123456789_abcdefghijklmnopqrstuvwxyz"
      constant = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789_abcdefghijklmnopqrstuvwxyz"

      result = Ruby::Prism.parse("# encoding: #{encoding.name}\n#{local} = 1\n#{local}\n#{constant}")
      assert result.success?

      write, read, constant_read = result.value.statements.body
      assert_equal local.to_sym, write.name
      assert_equal local.to_sym, read.name
      assert_equal constant.to_sym, constant_read.name
    end

    def assert_encoding_constant(name, character)
      result = Ruby::Prism.parse("# encoding: #{name}\n#{character}")
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of ConstantReadNode, actual
      assert_equal expected_name(name, character), actual.name
    end

    def assert_encoding_identifier(name, character)
      result = Ruby::Prism.parse("# encoding: #{name}\n#{character}")
      assert result.success?

      actual = result.value.statements.body.last
      assert_kind_of CallNode, actual
      assert_equal expected_name(name, character), actual.name
    end

    # Check that we can properly parse every codepoint in the given encoding.
    def assert_encoding(encoding, name, range)
      range = range.to_a - [0xb5] if encoding == Encoding::Windows_1253

      range.each do |codepoint|
        character = codepoint.chr(encoding)

        if constant_start?(character)
          assert_encoding_constant(name, character)
        elsif character.match?(/[[:alpha:]]/)
          assert_encoding_identifier(name, character)
        elsif character.match?(/[[:alnum:]]/)
          assert_encoding_identifier(name, "_#{character}")
        else
          next if ["/", "{"].include?(character)

          source = "# encoding: #{name}\n/(?##{character})/\n"
          assert Ruby::Prism.parse_success?(source), "Expected #{source.inspect} to parse successfully."
        end
      rescue RangeError
        source = "# encoding: #{name}\n\\x#{codepoint.to_s(16)}"
        assert Ruby::Prism.parse_failure?(source)
      end
    end
  end
end
