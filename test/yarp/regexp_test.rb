# frozen_string_literal: true

require "yarp_test_helper"

class RegexpTest < Test::Unit::TestCase
  ##############################################################################
  # These tests test the actual use case of extracting named capture groups
  ##############################################################################

  def test_named_captures_with_arrows
    assert_equal(["foo"], YARP.named_captures("(?<foo>bar)"))
  end

  def test_named_captures_with_single_quotes
    assert_equal(["foo"], YARP.named_captures("(?'foo'bar)"))
  end

  def test_nested_named_captures_with_arrows
    assert_equal(["foo", "bar"], YARP.named_captures("(?<foo>(?<bar>baz))"))
  end

  def test_nested_named_captures_with_single_quotes
    assert_equal(["foo", "bar"], YARP.named_captures("(?'foo'(?'bar'baz))"))
  end

  def test_allows_duplicate_named_captures
    assert_equal(["foo", "foo"], YARP.named_captures("(?<foo>bar)(?<foo>baz)"))
  end

  def test_named_capture_inside_fake_range_quantifier
    assert_equal(["foo"], YARP.named_captures("foo{1, (?<foo>2)}"))
  end

  ##############################################################################
  # These tests test the rest of the AST. They are not exhaustive, but they
  # should cover the most common cases. We test these to make sure we don't
  # accidentally regress and stop being able to extract named captures.
  ##############################################################################

  def test_alternation
    refute_nil(YARP.named_captures("foo|bar"))
  end

  def test_anchors
    refute_nil(YARP.named_captures("^foo$"))
  end

  def test_any
    refute_nil(YARP.named_captures("."))
  end

  def test_posix_character_classes
    refute_nil(YARP.named_captures("[[:digit:]]"))
  end

  def test_negated_posix_character_classes
    refute_nil(YARP.named_captures("[[:^digit:]]"))
  end

  def test_invalid_posix_character_classes_should_fall_back_to_regular_classes
    refute_nil(YARP.named_captures("[[:foo]]"))
  end

  def test_character_sets
    refute_nil(YARP.named_captures("[abc]"))
  end

  def test_nested_character_sets
    refute_nil(YARP.named_captures("[[abc]]"))
  end

  def test_nested_character_sets_with_operators
    refute_nil(YARP.named_captures("[[abc] && [def]]"))
  end

  def test_named_capture_inside_nested_character_set
    assert_equal([], YARP.named_captures("[foo (?<foo>bar)]"))
  end

  def test_negated_character_sets
    refute_nil(YARP.named_captures("[^abc]"))
  end

  def test_character_ranges
    refute_nil(YARP.named_captures("[a-z]"))
  end

  def test_negated_character_ranges
    refute_nil(YARP.named_captures("[^a-z]"))
  end

  def test_fake_named_captures_inside_character_sets
    assert_equal([], YARP.named_captures("[a-z(?<foo>)]"))
  end

  def test_fake_named_capture_inside_character_set_with_escaped_ending
    assert_equal([], YARP.named_captures("[a-z\\](?<foo>)]"))
  end

  def test_comments
    refute_nil(YARP.named_captures("(?#foo)"))
  end

  def test_non_capturing_groups
    refute_nil(YARP.named_captures("(?:foo)"))
  end

  def test_positive_lookaheads
    refute_nil(YARP.named_captures("(?=foo)"))
  end

  def test_negative_lookaheads
    refute_nil(YARP.named_captures("(?!foo)"))
  end

  def test_positive_lookbehinds
    refute_nil(YARP.named_captures("(?<=foo)"))
  end

  def test_negative_lookbehinds
    refute_nil(YARP.named_captures("(?<!foo)"))
  end

  def test_atomic_groups
    refute_nil(YARP.named_captures("(?>foo)"))
  end

  def test_absence_operator
    refute_nil(YARP.named_captures("(?~foo)"))
  end

  def test_conditional_expression_with_index
    refute_nil(YARP.named_captures("(?(1)foo)"))
  end

  def test_conditional_expression_with_name
    refute_nil(YARP.named_captures("(?(foo)bar)"))
  end

  def test_conditional_expression_with_group
    refute_nil(YARP.named_captures("(?(<foo>)bar)"))
  end

  def test_options_on_groups
    refute_nil(YARP.named_captures("(?imxdau:foo)"))
  end

  def test_options_on_groups_with_invalid_options
    assert_nil(YARP.named_captures("(?z:bar)"))
  end

  def test_options_on_groups_getting_turned_off
    refute_nil(YARP.named_captures("(?-imx:foo)"))
  end

  def test_options_on_groups_some_getting_turned_on_some_getting_turned_off
    refute_nil(YARP.named_captures("(?im-x:foo)"))
  end

  def test_star_quantifier
    refute_nil(YARP.named_captures("foo*"))
  end

  def test_plus_quantifier
    refute_nil(YARP.named_captures("foo+"))
  end

  def test_question_mark_quantifier
    refute_nil(YARP.named_captures("foo?"))
  end

  def test_endless_range_quantifier
    refute_nil(YARP.named_captures("foo{1,}"))
  end

  def test_beginless_range_quantifier
    refute_nil(YARP.named_captures("foo{,1}"))
  end

  def test_range_quantifier
    refute_nil(YARP.named_captures("foo{1,2}"))
  end

  def test_fake_range_quantifier_because_of_spaces
    refute_nil(YARP.named_captures("foo{1, 2}"))
  end
end
