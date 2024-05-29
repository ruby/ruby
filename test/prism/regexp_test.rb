# frozen_string_literal: true

require_relative "test_helper"

module Prism
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
      assert_valid_regexp("(?(1)foo)")
    end

    def test_conditional_expression_with_name
      assert_valid_regexp("(?(foo)bar)")
    end

    def test_conditional_expression_with_group
      assert_valid_regexp("(?(<foo>)bar)")
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
      option = Prism.parse_statement(regex).options

      assert_equal Regexp::FIXEDENCODING, option

      regex = "/foo/un"
      option = Prism.parse_statement(regex).options

      assert_equal Regexp::NOENCODING, option
    end

    private

    def assert_valid_regexp(source)
      assert Prism.parse_success?("/#{source}/ =~ \"\"")
    end

    def named_captures(source)
      Prism.parse("/#{source}/ =~ \"\"").value.locals
    end

    def options(flags)
      options =
        ["/foo/#{flags}", "/foo\#{1}/#{flags}"].map do |source|
          Prism.parse_statement(source).options
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
