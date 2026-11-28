# frozen_string_literal: true

require_relative "test_helper"

module Ruby::Prism
  class RegexpTest < TestCase
    ############################################################################
    # These tests test the actual use case of extracting named capture groups
    ############################################################################

    def test_named_captures_with_arrows
      assert_equal([:foo], named_captures("(?<foo>bar)"))
    end

    def test_named_captures_with_single_quotes
      assert_equal([:foo], named_captures("(?'foo'bar)"))
    end

    def test_nested_named_captures_with_arrows
      assert_equal([:foo, :bar], named_captures("(?<foo>(?<bar>baz))"))
    end

    def test_nested_named_captures_with_single_quotes
      assert_equal([:foo, :bar], named_captures("(?'foo'(?'bar'baz))"))
    end

    def test_allows_duplicate_named_captures
      assert_equal([:foo], named_captures("(?<foo>bar)(?<foo>baz)"))
    end

    def test_named_references_after_the_capture_index_grows
      pattern = Array.new(64) { |index| "(?<n#{index}>a)\\k<n#{index}>" }.join
      assert_empty Ruby::Prism.parse("/\\g<n63>#{pattern}/").errors

      pattern += "(?<n0>b)\\g<n0>"
      assert_equal ["multiplex definition name <n0> call: /#{pattern}/"], Ruby::Prism.parse("/#{pattern}/").errors.map(&:message)
    end

    def test_named_capture_with_a_comment_in_its_name
      result = Ruby::Prism.parse('/(?<a(?#comment)b>x)/ =~ ab; ab')
      assert_empty result.errors
      assert_equal [:ab], result.value.locals

      match, read = result.value.statements.body
      assert_equal [:ab], match.targets.map(&:name)
      assert_equal "a(?#comment)b", match.targets.first.location.slice
      assert_kind_of CallNode, match.call.arguments.arguments.first
      assert_kind_of LocalVariableReadNode, read
    end

    def test_named_captures_from_unicode_escapes
      result = Ruby::Prism.parse('/(?<\\u3042>x)(?<\\u0061>y)/ =~ ""')
      assert_empty result.errors
      assert_equal [:あ], result.value.locals
      assert_equal "\\u3042", result.value.statements.body.first.targets.first.location.slice
    end

    def test_named_capture_locals_when_a_unicode_escape_sets_the_regexp_encoding
      source = '/(?<\ueee5>)(?<ascii>)(?<a\u3042>)\k<\ueee5>/ =~ ""'
      self.class.each_encoding([Encoding::CESU_8, Encoding::ASCII_8BIT, Encoding::UTF_8]) do |encoding|
        result = Ruby::Prism.parse(source, encoding: encoding)
        assert_empty result.errors, encoding.name

        expected = encoding == Encoding::UTF_8 ? [:"\uEEE5", :ascii, :aあ] : [:ascii]
        assert_equal expected, result.value.locals, encoding.name
        assert_equal expected, result.statement.targets.map(&:name), encoding.name
      end
    end

    def test_non_ascii_named_capture_in_a_binary_regexp
      source = '/(?<\xC3\xA9>)/n =~ ""'
      binary = Ruby::Prism.parse(source, encoding: Encoding::ASCII_8BIT)
      assert_empty binary.errors
      assert_equal ["\xC3\xA9".b.to_sym], binary.value.locals

      utf8 = Ruby::Prism.parse(source, encoding: Encoding::UTF_8)
      assert_empty utf8.errors
      assert_empty utf8.value.locals
      assert_kind_of CallNode, utf8.statement
    end

    def test_nested_matches_keep_their_own_captures
      result = Ruby::Prism.parse('/(?<outer>x)/ =~ (/(?<inner>y)/ =~ "y"); [outer, inner]')
      assert_empty result.errors
      assert_equal [:inner, :outer], result.value.locals
      assert_equal :outer, result.value.statements.body.first.targets.first.name
    end

    def test_named_captures_after_range_of_escapes
      assert_equal([:foo], named_captures("[\\u{61}-\\u{7a}](?<foo>bar)"))
    end

    def test_named_captures_after_range_of_escaped_multibyte_character
      assert_equal([:foo], named_captures("[!-\\xE3\\x81\\x82-\\p{Alpha}](?<foo>bar)"))
    end

    def test_named_capture_inside_fake_range_quantifier
      assert_equal([:foo], named_captures("foo{1, (?<foo>2)}"))
    end

    def test_fake_named_captures_inside_character_sets
      assert_equal([], named_captures("[a-z(?<foo>)]"))
    end

    def test_fake_named_capture_inside_character_set_with_escaped_ending
      assert_equal([], named_captures("[a-z\\](?<foo>)]"))
    end

    ############################################################################
    # These tests test the rest of the AST. They are not exhaustive, but they
    # should cover the most common cases. We test these to make sure we don't
    # accidentally regress and stop being able to extract named captures.
    ############################################################################

    def test_alternation
      assert_valid_regexp("foo|bar")
    end

    def test_anchors
      assert_valid_regexp("^foo$")
    end

    def test_any
      assert_valid_regexp(".")
    end

    def test_posix_character_classes
      assert_valid_regexp("[[:digit:]]")
    end

    def test_negated_posix_character_classes
      assert_valid_regexp("[[:^digit:]]")
    end

    def test_invalid_posix_character_classes_should_fall_back_to_regular_classes
      assert_valid_regexp("[[:foo]]")
    end

    def test_character_sets
      assert_valid_regexp("[abc]")
    end

    def test_nested_character_sets
      assert_valid_regexp("[[abc]]")
    end

    def test_nested_character_sets_with_operators
      assert_valid_regexp("[[abc] && [def]]")
    end

    def test_named_capture_inside_nested_character_set
      assert_equal([], named_captures("[foo (?<foo>bar)]"))
    end

    def test_negated_character_sets
      assert_valid_regexp("[^abc]")
    end

    def test_character_ranges
      assert_valid_regexp("[a-z]")
    end

    def test_negated_character_ranges
      assert_valid_regexp("[^a-z]")
    end

    def test_comments
      assert_valid_regexp("(?#foo)")
    end

    def test_comments_with_escaped_parentheses
      assert_valid_regexp("(?#foo\\)\\))")
    end

    def test_non_capturing_groups
      assert_valid_regexp("(?:foo)")
    end

    def test_positive_lookaheads
      assert_valid_regexp("(?=foo)")
    end

    def test_negative_lookaheads
      assert_valid_regexp("(?!foo)")
    end

    def test_positive_lookbehinds
      assert_valid_regexp("(?<=foo)")
    end

    def test_negative_lookbehinds
      assert_valid_regexp("(?<!foo)")
    end

    def test_atomic_groups
      assert_valid_regexp("(?>foo)")
    end

    def test_absence_operator
      assert_valid_regexp("(?~foo)")
    end

    def test_conditional_expression_with_index
      assert_valid_regexp("(a)(?(1)foo)")
    end

    def test_conditional_expression_with_name
      assert_valid_regexp("(?<foo>a)(?('foo')bar)")
    end

    def test_conditional_expression_with_group
      assert_valid_regexp("(?<foo>a)(?(<foo>)bar)")
    end

    def test_options_on_groups
      assert_valid_regexp("(?imxdau:foo)")
    end

    def test_options_on_groups_getting_turned_off
      assert_valid_regexp("(?-imx:foo)")
    end

    def test_options_on_groups_some_getting_turned_on_some_getting_turned_off
      assert_valid_regexp("(?im-x:foo)")
    end

    def test_star_quantifier
      assert_valid_regexp("foo*")
    end

    def test_plus_quantifier
      assert_valid_regexp("foo+")
    end

    def test_question_mark_quantifier
      assert_valid_regexp("foo?")
    end

    def test_endless_range_quantifier
      assert_valid_regexp("foo{1,}")
    end

    def test_beginless_range_quantifier
      assert_valid_regexp("foo{,1}")
    end

    def test_range_quantifier
      assert_valid_regexp("foo{1,2}")
    end

    def test_fake_range_quantifier_because_of_spaces
      assert_valid_regexp("foo{1, 2}")
    end

    def test_fake_range_quantifier_because_unclosed
      assert_valid_regexp("\\A{")
    end

    ############################################################################
    # These test that flag values are correct.
    ############################################################################

    def test_flag_ignorecase
      assert_equal(Regexp::IGNORECASE, options("i"))
    end

    def test_flag_extended
      assert_equal(Regexp::EXTENDED, options("x"))
    end

    def test_flag_multiline
      assert_equal(Regexp::MULTILINE, options("m"))
    end

    def test_flag_fixedencoding
      assert_equal(Regexp::FIXEDENCODING, options("e"))
      assert_equal(Regexp::FIXEDENCODING, options("u"))
      assert_equal(Regexp::FIXEDENCODING, options("s"))
    end

    def test_flag_noencoding
      assert_equal(Regexp::NOENCODING, options("n"))
    end

    def test_flag_once
      assert_equal(0, options("o"))
    end

    def test_flag_combined
      value = Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED
      assert_equal(value, options("mix"))
    end

    def test_last_encoding_option_wins
      regex = "/foo/nu"
      option = Ruby::Prism.parse_statement(regex).options

      assert_equal Regexp::FIXEDENCODING, option

      regex = "/foo/un"
      option = Ruby::Prism.parse_statement(regex).options

      assert_equal Regexp::NOENCODING, option
    end

    # A `%r` regexp can use a newline (LF or CRLF) as its delimiter. The closing
    # delimiter terminates the regexp and must not be misread as an option -- in
    # particular the trailing `\n` of a `\r\n` delimiter.
    def test_newline_delimiter
      assert_newline_regexp("%r\nfoo\n", "foo", 0)
      assert_newline_regexp("%r\r\nfoo\r\n", "foo", 0)
      assert_newline_regexp("%r\r\nfoo\r\ni", "foo", Regexp::IGNORECASE)
      assert_newline_regexp("%r\r\nfoo\r\nmix", "foo", Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED)
      assert_newline_regexp("%r\r\n\r\n", "", 0)
    end

    # With a heredoc body pending when a newline delimiter closes the regexp, the
    # options are read from the line following that body.
    def test_newline_delimiter_options_after_heredoc
      assert_options_after_heredoc("\ni", Regexp::IGNORECASE, "%r\n\#{<<A}\nbody\nA\ni\n")
      assert_options_after_heredoc("\nmix", Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED, "%r\n\#{<<A}\nbody\nA\nmix\n")
      assert_options_after_heredoc("\ni", Regexp::IGNORECASE, "%r\r\n\#{<<A}\r\nbody\r\nA\r\ni\r\n")
      assert_options_after_heredoc("\n", 0, "%r\n\#{<<A}\nbody\nA\n")
    end

    # The closing location runs from the newline ending the heredoc body through
    # the options, so it has the same shape as any newline delimiter with options.
    def test_newline_delimiter_options_after_heredoc_location
      node = Ruby::Prism.parse("%r\n\#{<<A}\nbody\nA\ni\n").value.statements.body.first

      assert_equal 16, node.closing_loc.start_offset
      assert_equal 18, node.closing_loc.end_offset
      assert_equal 18, node.location.end_offset
    end

    def test_newline_delimiter_options_after_heredoc_continues_after_options
      result = Ruby::Prism.parse("%r\n\#{<<A}\nbody\nA\ni.source\n")
      assert_empty result.errors

      node = result.value.statements.body.first
      assert_equal :source, node.name
      assert_equal Regexp::IGNORECASE, node.receiver.options
    end

    def test_newline_delimiter_unknown_options_after_heredoc
      errors = Ruby::Prism.parse("%r\n\#{<<A}\nbody\nA\nfoo\n").errors
      assert_equal ["unknown regexp option - f"], errors.map(&:message)
    end

    def test_malformed_control_and_meta_escapes
      assert_equal "\\x80-a", Ruby::Prism.parse_statement("/\\M-\\M-a/").unescaped
      assert_equal "(\\x00", Ruby::Prism.parse_statement("/(\\cé/").unescaped
      assert_equal "\\x00a(", Ruby::Prism.parse_statement("/\\C-\\C-a(/").unescaped
    end

    def test_crlf_in_braced_unicode_escape
      assert_equal "\\u{E\r\n}", Ruby::Prism.parse_statement("/\\u{E\r\n}/").unescaped

      result = Ruby::Prism.parse("%r!\\u{41\r\n42\r\n}\r\n!")
      assert_empty result.errors
      assert_equal "\\u{41\r\n42\n}\n", result.statement.unescaped
      assert_equal 4, result.statement.closing_loc.start_line
    end

    def test_braced_unicode_escape_at_newline_delimiter
      result = Ruby::Prism.parse("%r\n#\\u{E\r\nx")
      assert_empty result.errors
      assert_equal "#\\u{E\r", result.statement.unescaped
      assert_equal "\r\nx", result.statement.closing_loc.slice

      result = Ruby::Prism.parse("%r\n#\\u{E\\\n}\nx")
      assert_empty result.errors
      assert_equal "#\\u{E\\\n}", result.statement.unescaped
      assert_equal 3, result.statement.closing_loc.start_line
    end

    def test_malformed_unicode_list_does_not_close_brace_delimited_regexp
      ["\\u{s}", "\\u{41 z}", "\\u{z\\}z}"].each do |escape|
        source = "if false; %r{ #{escape} } + 1; end"
        result = Ruby::Prism.parse(source)

        assert_equal ["invalid Unicode list: / #{escape} /"], result.errors.map(&:message)
        addition = result.value.statements.body.first.statements.body.first
        assert_equal :+, addition.name
        assert_equal " #{escape} ", addition.receiver.unescaped
        assert_equal source.rindex("}"), addition.receiver.closing_loc.start_offset
      end
    end

    def test_malformed_unicode_lists_in_regexp_comments
      ["\\C", "\\M", "\\x"].each do |inner|
        escape = "\\u{" + inner
        assert_empty Ruby::Prism.parse("/(?#" + escape + ")/").errors
        assert_empty Ruby::Prism.parse("/#" + escape + "\n/x").errors
        assert_empty Ruby::Prism.parse("%r!(?#" + escape + ")!").errors
        assert_empty Ruby::Prism.parse("%r{(?#" + escape + "})}").errors
        assert_equal ["invalid Unicode list: /#{escape}/"], Ruby::Prism.parse("%r!" + escape + "!").errors.map(&:message)
      end
    end

    def test_malformed_hex_escape
      node = Ruby::Prism.parse_statement("/a\\xZb/")
      assert_kind_of RegularExpressionNode, node
      assert_equal "aZb", node.unescaped
    end

    # A string that interpolates only string literals has a value known while
    # parsing, so a regular expression that interpolates it is validated as the
    # one that its parts join to. parse.y builds this one each time it is
    # evaluated instead, which raises then.
    def test_static_interpolation_of_interpolated_string
      errors = Ruby::Prism.parse('/a#{"b#{"c"}"}(/').errors
      assert_equal ["end pattern with unmatched parenthesis: /abc(/"], errors.map(&:message)
    end

    def test_invalid_interpolated_regexp_in_unevaluated_code
      assert_equal [:regexp_parse_error], Ruby::Prism.parse('if false; /#{"["}/; end').errors.map(&:type)
      assert_equal [:invalid_multibyte_escape], Ruby::Prism.parse('defined? /\M- #@f/').errors.map(&:type)
      assert_empty Ruby::Prism.parse('defined? /#{"["}#{value}/').errors
    end

    def test_encoding_option_on_interpolated_bytes
      ['/#{"\xcd"} /n', '/#{"\xcd"}/n', 'defined? /#{"\xcd"}#{value}/n'].each do |source|
        errors = Ruby::Prism.parse(source).errors
        assert_equal ["regexp encoding option 'n' differs from source encoding 'UTF-8'"], errors.map(&:message), source
        assert_equal '"\xcd"', errors.first.location.slice
      end

      assert_empty Ruby::Prism.parse('/#{"\x41"} /n').errors
      assert_empty Ruby::Prism.parse('/#{"\xcd"} /n', encoding: Encoding::ASCII_8BIT).errors
      assert_empty Ruby::Prism.parse('/\xcd#{value}/n').errors

      errors = Ruby::Prism.parse('/#{"\xff"}#{value}#{"\xcd"}/n').errors
      assert_equal [:regexp_encoding_option_mismatch] * 2, errors.map(&:type)
      assert_equal ['"\xff"', '"\xcd"'], errors.map { |error| error.location.slice }
    end

    def test_leading_semicolon_in_regexp_interpolation
      assert_empty Ruby::Prism.parse('/#{; "["}/').errors
      assert_empty Ruby::Prism.parse(%q{/#{; '\x'}/}).errors
      assert_equal [:regexp_parse_error], Ruby::Prism.parse(%q{/#{'\x';}/}).errors.map(&:type)
    end

    # The content that a regular expression's parts join to takes the encoding
    # of its parts that are not ASCII, as joining strings does, so a string in
    # UTF-8 makes the content UTF-8 in a source in another encoding.
    def test_static_interpolation_in_another_encoding
      assert_empty Ruby::Prism.parse("# encoding: EUC-JP\n" + '/a#{"\\u3042"}/').errors

      # The message is in the encoding of the source, but it quotes the content
      # in UTF-8, so its bytes are compared.
      errors = Ruby::Prism.parse("# encoding: EUC-JP\n" + '/a#{"\\u3042"}(/').errors
      assert_equal ["end pattern with unmatched parenthesis: /aあ(/".b], errors.map { |error| error.message.b }
    end

    # In a US-ASCII source, every part of a regular expression without an
    # encoding option is binary, so a UTF-8 string joins a binary one.
    def test_static_interpolation_in_us_ascii
      assert_empty Ruby::Prism.parse("# encoding: US-ASCII\n" + '/#{"\\u3042"}#{"\\xFF"}/').errors
    end

    def test_static_interpolation_of_incompatible_encodings
      source = "# encoding: EUC-JP\n/\xA4\xA2".b + '#{"\\u3042"}/'
      errors = Ruby::Prism.parse(source).errors
      assert_equal ["incompatible character encodings: EUC-JP and UTF-8"], errors.map(&:message)
    end

    def test_static_interpolation_raises_encoding_compatibility_error
      source = "# encoding: Windows-31J\n".b + '/#{"\u1234"}#{"' + "\x82\xA0".b + '"}/'
      message = "incompatible character encodings: UTF-8 and Windows-31J"

      errors = Ruby::Prism.parse(source).errors
      assert_equal [[:regexp_interpolation_encoding, :encoding_compatibility, message]], errors.map { |error| [error.type, error.level, error.message] }

      error = assert_raise(Encoding::CompatibilityError) { Ruby::Prism.parse(source, raise_error: :plain) }
      assert_equal message, error.message
      assert_raise(SyntaxError) { Ruby::Prism.parse(source + "\n)", raise_error: :plain) }
    end

    # A comment in extended mode ends at the newline, so the * after it has
    # nothing to repeat. The error quotes the pattern with its newline.
    def test_repeat_after_extended_comment
      errors = Ruby::Prism.parse("/( # comment\n*)/x").errors

      assert_equal ["target of repeat operator is not specified: /( # comment\n*)/x"], errors.map(&:message)
      assert_equal [2, 0], [errors.first.location.start_line, errors.first.location.start_column]
    end

    def test_regexp_recovery_limits_repeated_pattern_quotes
      pattern = ")" * 4000
      errors = Ruby::Prism.parse("/#{pattern}/").errors

      assert_equal pattern.length, errors.length
      assert_equal "unmatched close parenthesis: /#{pattern}/", errors.first.message
      assert_equal ")", errors.last.location.slice
      assert_operator errors.sum { |error| error.message.bytesize }, :<, pattern.bytesize * 50
    end

    def test_nul_in_a_regexp_reference_name
      reference = "\\k<n\0x>"
      error = Ruby::Prism.parse("/#{reference}/i").errors.fetch(0)
      assert_equal "undefined name <n: /\\k<n\\x00x>/i", error.message
      assert_equal "n\0x", error.location.slice

      errors = Ruby::Prism.parse("/#{")" * 8}#{reference}/i").errors
      assert_equal "undefined name <n", errors.fetch(8).message
    end

    def test_unicode_escapes_in_regexp_error
      errors = Ruby::Prism.parse("%r!/\u0080\uFFFF\u{10000}\u{10FFFF}(!").errors
      assert_equal ['end pattern with unmatched parenthesis: /\/\u0080\uFFFF\u{10000}\u{10FFFF}(/'], errors.map(&:message)
    end

    def test_depth_limit_nested_character_sets
      assert_depth_limit("[" * 10_000)
    end

    # Each of these groups turns extended mode on or off, and the escape inside
    # them makes their escapes be read, which follows each such group.
    def test_depth_limit_groups_that_toggle_extended_mode
      groups = Array.new(100_000) { |index| index.even? ? "(?x:" : "(?-x:" }
      assert_depth_limit("#{groups.join}\\x41#{")" * groups.length}")
    end

    private

    def assert_depth_limit(source)
      messages = Ruby::Prism.parse("/#{source}/ =~ \"\"").errors.map(&:message)
      assert_equal 1, messages.count { |message| message.start_with?("parse depth limit over: /") }
    end

    def assert_options_after_heredoc(closing, options, source)
      result = Ruby::Prism.parse(source)
      assert_empty result.errors, source.inspect

      node = result.value.statements.body.first
      assert_equal closing, node.closing, source.inspect
      assert_equal options, node.options, source.inspect
    end

    def assert_newline_regexp(source, content, options)
      node = Ruby::Prism.parse_statement(source)

      assert_kind_of RegularExpressionNode, node
      assert_equal content, node.content
      assert_equal options, node.options
    end

    def assert_valid_regexp(source)
      assert Ruby::Prism.parse_success?("/#{source}/ =~ \"\"")
    end

    def named_captures(source)
      Ruby::Prism.parse("/#{source}/ =~ \"\"").value.locals
    end

    def options(flags)
      options =
        ["/foo/#{flags}", "/foo\#{1}/#{flags}"].map do |source|
          Ruby::Prism.parse_statement(source).options
        end

      # Check that we get the same set of options from both regular expressions
      # and interpolated regular expressions.
      assert_equal(1, options.uniq.length)

      # Return the options from the first regular expression since we know they
      # are the same.
      options.first
    end
  end
end
