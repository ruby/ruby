# frozen_string_literal: true

return if RUBY_VERSION < "3.3.0"

require_relative "test_helper"

module Ruby::Prism
  class ErrorsTest < TestCase
    base = File.expand_path("errors", __dir__)
    filepaths = Dir[ENV.fetch("FOCUS", "**/*.txt"), base: base]

    PARSE_Y_EXCLUDES = [
      # https://bugs.ruby-lang.org/issues/20409
      "#{base}/4.1/end_block_exit.txt"
    ]

    filepaths.each do |filepath|
      ruby_versions_for(filepath).each do |version|
        define_method(:"test_#{version}_#{File.basename(filepath, ".txt")}") do
          assert_errors(File.join(base, filepath), version)
        end
      end
    end

    def test_unterminated_quoted_symbol_closing_location
      {
        ':"#s' => :symbol_term_interpolated,
        ':"#{x}' => :symbol_term_interpolated,
        ":'s" => :symbol_term_dynamic
      }.each do |source, diagnostic|
        result = Ruby::Prism.parse(source)
        symbol = result.value.statements.body.first

        assert_equal [diagnostic], result.errors.map(&:type)
        assert_equal source, symbol.location.slice
        assert_nil symbol.closing_loc
      end
    end

    def test_unclosed_array_location_covers_last_element
      source = '[r="#{ '
      result = Ruby::Prism.parse(source)
      array = result.value.statements.body.first

      assert_includes result.errors.map(&:type), :array_term
      assert_nil array.closing_loc
      assert_equal source, array.location.slice
      assert_equal array.elements.last.location.end_offset, array.location.end_offset
    end

    def test_implicit_method_rescue_rejects_constant_target
      ["", "StandardError "].each do |exceptions|
        result = Ruby::Prism.parse("def f; raise; rescue #{exceptions}=> CaughtError; end")

        assert_equal [:write_target_in_method], result.errors.map(&:type)
        assert_equal "CaughtError", result.errors.first.location.slice
      end
    end

    def test_endless_method_rescue_rejects_unattached_do_block
      result = Ruby::Prism.parse("relay def f = 1 rescue 2 do end")

      assert_equal [:def_endless_do_block], result.errors.map(&:type)
      assert_equal "do end", result.errors.first.location.slice
    end

    def test_module_name_rejects_symbol_ending_in_constant_token
      result = Ruby::Prism.parse("module:A; end")

      assert_equal [:module_name], result.errors.map(&:type)
      assert_equal ":A", result.errors.first.location.slice
    end

    def test_begin_with_rescue_and_ensure_rejects_void_values
      result = Ruby::Prism.parse("def f; x = begin; return :body; rescue; return :rescue; ensure; end; end")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_equal "return :body", result.errors.first.location.slice

      result = Ruby::Prism.parse("def f; x = begin; return :body; rescue; 1; ensure; return :ensure; end; end")
      assert_equal [:void_expression], result.errors.map(&:type)
      assert_equal "return :ensure", result.errors.first.location.slice
    end

    def test_parenthesized_targets_reject_newline_before_assignment
      ["(first, second\n= [1, 2])", "((first, second), third\n= [1, 2, 3])"].each do |source|
        result = Ruby::Prism.parse(source)

        assert_equal [:write_target_unexpected], result.errors.map(&:type), source
      end
    end

    def test_class_headers_respect_enclosing_loop_condition
      ["while", "until"].each do |keyword|
        result = Ruby::Prism.parse("#{keyword} class << target do end; end; end")

        assert_includes result.errors.map(&:type), :expect_singleton_class_delimiter
      end

      result = Ruby::Prism.parse("while class A < target do end; end; end")
      assert_includes result.errors.map(&:type), :class_unexpected_end
    end

    def test_singleton_method_definition_rejects_setter_name_as_receiver
      [".", "::"].each do |operator|
        result = Ruby::Prism.parse("def target=#{operator}greet; end")

        assert_equal [:def_receiver_setter], result.errors.map(&:type)
        assert_equal "target=", result.errors.first.location.slice
      end
    end

    def test_uppercase_shorthand_hash_labels_reject_method_suffixes
      ["Flag?", "Status!"].each do |name|
        result = Ruby::Prism.parse("{ #{name}: }")

        assert_equal [:invalid_constant_read], result.errors.map(&:type)
        assert_equal name, result.errors.first.location.slice
      end

      assert_equal [:invalid_local_variable_read], Ruby::Prism.parse("{ flag?: }").errors.map(&:type)
    end

    def test_colon_delimited_percent_symbol_requires_hash_rocket
      result = Ruby::Prism.parse("{ %s:: 1 }")
      assert_equal [:hash_rocket], result.errors.map(&:type)
    end

    def test_beginless_range_rejects_unparenthesized_binary_range_operand
      assert_equal [:unexpected_range_operator], Ruby::Prism.parse("p(...1..2)").errors.map(&:type)
    end

    def test_leading_logical_label_does_not_turn_following_keyword_into_symbol
      ["and", "or"].each do |keyword|
        result = Ruby::Prism.parse("show\n#{keyword}:then", version: "4.0")

        assert_predicate result, :failure?
        assert_equal "then", result.errors.first.location.slice
      end
    end

    def test_keyword_not_is_not_a_write_target
      [
        "not() = :value",
        "*not() = value",
        "first, not() = 1, 2",
        "begin; rescue => not(); end",
        "for not() in []; end",
        "not() |= 42",
        "not() &&= 1",
        "not() ||= 1",
        "not flag.. ||= 1"
      ].each do |source|
        assert_equal [:write_target_unexpected], Ruby::Prism.parse(source).errors.map(&:type), source
      end
    end

    def test_mixed_encoding_locations
      ["ASCII-8BIT", "US-ASCII", "EUC-JP"].each do |encoding|
        next if ENV["PRISM_BUILD_MINIMAL"] && encoding == "EUC-JP"

        bytes = encoding == "EUC-JP" ? "\xA1\xA1" : "\xA1"
        source = "\"\\u{df}abc#{bytes}\"".b
        error = Ruby::Prism.parse(source, encoding: encoding).errors.find { |diagnostic| diagnostic.type == :mixed_encoding }

        assert_not_nil error
        assert_equal 10, error.location.start_offset
        assert_equal bytes.bytesize, error.location.length
        assert_equal bytes.b, error.location.slice.b
      end
    end

    def test_mixed_encoding_location_for_invalid_multibyte_character
      return if ENV["PRISM_BUILD_MINIMAL"]

      source = "\"\\u{df\xD3&".b
      error = Ruby::Prism.parse(source, encoding: "EUC-JP").errors.find { |diagnostic| diagnostic.type == :mixed_encoding }

      assert_not_nil error
      assert_equal 6, error.location.start_offset
      assert_equal 1, error.location.length
      assert_equal "\xD3".b, error.location.slice.b
    end

    def test_extra_unicode_codepoint_locations
      ["a", "00", "a b", "a "].each do |extra|
        result = Ruby::Prism.parse("?\\u{0 #{extra}}")
        error = result.errors.find { |diagnostic| diagnostic.type == :escape_invalid_unicode_literal }

        assert_not_nil error
        assert_equal 6, error.location.start_offset
        assert_equal extra, error.location.slice
      end
    end

    def test_newline_preceding_eof
      err = Ruby::Prism.parse("foo(").errors.first
      assert_equal 1, err.location.start_line

      err = Ruby::Prism.parse("foo(\n").errors.first
      assert_equal 1, err.location.start_line

      err = Ruby::Prism.parse("foo(\n\n\n\n\n").errors.first
      assert_equal 5, err.location.start_line
    end

    def test_embdoc_beginning_control_characters
      ["\0", "\C-d", "\C-z"].each do |character|
        ["\n", "\r\n"].each do |newline|
          comment = "=begin#{character}#{newline}ignored#{newline}=end#{newline}"
          result = Ruby::Prism.parse("#{comment}1#{newline}")

          assert_predicate result, :success?
          assert_equal 1, result.statement.value
          assert_equal 1, result.comments.length
          assert_kind_of EmbDocComment, result.comments.first
          assert_equal comment, result.comments.first.location.slice
        end
      end
    end

    def test_unterminated_embdoc_after_control_character
      ["\C-d", "\C-z"].each do |character|
        result = Ruby::Prism.parse("=begin#{character}")
        assert_equal [:embdoc_term], result.errors.map(&:type)
      end
    end

    def test_embdoc_ending
      source = <<~RUBY
        =begin\n=end
        =begin\n=end\0
        =begin\n=end\C-d
        =begin\n=end\C-z
      RUBY

      source.each_line do |line|
        assert_valid_syntax(source)
        assert_predicate Ruby::Prism.parse(source), :success?
      end
    end

    def test_unterminated_string_closing
      statement = Ruby::Prism.parse_statement("'hello")
      assert_equal statement.unescaped, "hello"
      assert_nil statement.closing
    end

    def test_unterminated_interpolated_string_closing
      statement = Ruby::Prism.parse_statement('"hello')
      assert_equal statement.unescaped, "hello"
      assert_nil statement.closing
    end

    def test_unterminated_empty_string_closing
      statement = Ruby::Prism.parse_statement('"')
      assert_empty statement.unescaped
      assert_nil statement.closing
    end

    def test_unterminated_string_with_an_invalid_unicode_escape
      result = Ruby::Prism.parse('"\u{xxxx')
      statement = result.value.statements.body.first
      assert_kind_of StringNode, statement
      assert_equal '\u{xxxx', statement.content
      assert_nil statement.closing

      assert_equal [:escape_invalid_unicode, :escape_invalid_unicode_term, :string_interpolated_term], result.errors.map(&:type)
      assert_equal [4, 4, 0], result.errors.map { |error| error.location.start_offset }
    end

    def test_regexp_encoding_option_mismatch_error
      # UTF-8 char with ASCII-8BIT modifier
      result = Ruby::Prism.parse('/Ȃ/n')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with EUC-JP modifier
      result = Ruby::Prism.parse('/Ȃ/e')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with Windows-31J modifier
      result = Ruby::Prism.parse('/Ȃ/s')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with UTF-8 modifier
      result = Ruby::Prism.parse('/Ȃ/u')
      assert_empty result.errors
    end

    def test_long_formatted_messages
      # Messages are formatted into a fixed-size buffer first, so check lengths
      # on either side of its size to cover both the copy and the reformat.
      template = "unterminated heredoc; can't find string \"%s\" anywhere before EOF"

      (254..258).each do |length|
        identifier = "E" * (length - template.length + 2)
        expected = format(template, identifier)
        assert_equal length, expected.bytesize

        messages = Ruby::Prism.parse("<<#{identifier}\n").errors.map(&:message)
        assert_includes messages, expected
      end
    end

    def test_incomplete_def_closing_loc
      statement = Ruby::Prism.parse_statement("def f; 123")
      assert_nil(statement.end_keyword)
    end

    def test_unclosed_interpolation
      statement = Ruby::Prism.parse_statement("\"\#{")
      assert_equal('"', statement.opening)
      assert_nil(statement.closing)

      assert_equal(1, statement.parts.count)
      assert_equal('#{', statement.parts[0].opening)
      assert_equal("", statement.parts[0].closing)
      assert_nil(statement.parts[0].statements)
    end

    def test_unclosed_heredoc_and_interpolation
      statement = Ruby::Prism.parse_statement("<<D\n\#{")
      assert_equal("<<D", statement.opening)
      assert_nil(statement.closing)

      assert_equal(1, statement.parts.count)
      assert_equal('#{', statement.parts[0].opening)
      assert_equal("", statement.parts[0].closing)
      assert_nil(statement.parts[0].statements)
    end

    private

    def assert_errors(filepath, version)
      expected = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      source = expected.lines.grep_v(/^\s*\^/).join.gsub(/\n*\z/, "")
      if CURRENT_MAJOR_MINOR == version && !PARSE_Y_EXCLUDES.include?(filepath)
        refute_valid_syntax(source)
      end

      result = Ruby::Prism.parse(source, version: version)
      errors = result.errors
      refute_empty errors, "Expected errors in #{filepath}"

      actual = result.errors_format
      if expected != actual && ENV["UPDATE_SNAPSHOTS"]
        File.write(filepath, actual)
      end

      assert_equal expected, actual, "Expected errors to match for #{filepath}"
    end
  end
end
