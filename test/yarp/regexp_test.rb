# frozen_string_literal: true

require "test_helper"

class RegexpTest < Test::Unit::TestCase
  ##############################################################################
  # These tests test the actual use case of extracting named capture groups
  ##############################################################################

  test "named captures with <>" do
    assert_equal(["foo"], YARP.named_captures("(?<foo>bar)"))
  end

  test "named captures with ''" do
    assert_equal(["foo"], YARP.named_captures("(?'foo'bar)"))
  end

  test "nested named captures with <>" do
    assert_equal(["foo", "bar"], YARP.named_captures("(?<foo>(?<bar>baz))"))
  end

  test "nested named captures with ''" do
    assert_equal(["foo", "bar"], YARP.named_captures("(?'foo'(?'bar'baz))"))
  end

  test "allows duplicate named captures" do
    assert_equal(["foo", "foo"], YARP.named_captures("(?<foo>bar)(?<foo>baz)"))
  end

  test "named capture inside fake range quantifier" do
    assert_equal(["foo"], YARP.named_captures("foo{1, (?<foo>2)}"))
  end

  ##############################################################################
  # These tests test the rest of the AST. They are not exhaustive, but they
  # should cover the most common cases. We test these to make sure we don't
  # accidentally regress and stop being able to extract named captures.
  ##############################################################################

  test "alternation" do
    refute_nil(YARP.named_captures("foo|bar"))
  end

  test "anchors" do
    refute_nil(YARP.named_captures("^foo$"))
  end

  test "any" do
    refute_nil(YARP.named_captures("."))
  end

  test "posix character classes" do
    refute_nil(YARP.named_captures("[[:digit:]]"))
  end

  test "negated posix character classes" do
    refute_nil(YARP.named_captures("[[:^digit:]]"))
  end

  test "invalid posix character classes should fall back to regular classes" do
    refute_nil(YARP.named_captures("[[:foo]]"))
  end

  test "character sets" do
    refute_nil(YARP.named_captures("[abc]"))
  end

  test "nested character sets" do
    refute_nil(YARP.named_captures("[[abc]]"))
  end

  test "nested character sets with operators" do
    refute_nil(YARP.named_captures("[[abc] && [def]]"))
  end

  test "named capture inside nested character set" do
    assert_equal([], YARP.named_captures("[foo (?<foo>bar)]"))
  end

  test "negated character sets" do
    refute_nil(YARP.named_captures("[^abc]"))
  end

  test "character ranges" do
    refute_nil(YARP.named_captures("[a-z]"))
  end

  test "negated character ranges" do
    refute_nil(YARP.named_captures("[^a-z]"))
  end

  test "fake named captures inside character sets" do
    assert_equal([], YARP.named_captures("[a-z(?<foo>)]"))
  end

  test "fake named capture inside character set with escaped ending" do
    assert_equal([], YARP.named_captures("[a-z\\](?<foo>)]"))
  end

  test "comments" do
    refute_nil(YARP.named_captures("(?#foo)"))
  end

  test "non-capturing groups" do
    refute_nil(YARP.named_captures("(?:foo)"))
  end

  test "positive lookaheads" do
    refute_nil(YARP.named_captures("(?=foo)"))
  end

  test "negative lookaheads" do
    refute_nil(YARP.named_captures("(?!foo)"))
  end

  test "positive lookbehinds" do
    refute_nil(YARP.named_captures("(?<=foo)"))
  end

  test "negative lookbehinds" do
    refute_nil(YARP.named_captures("(?<!foo)"))
  end

  test "atomic groups" do
    refute_nil(YARP.named_captures("(?>foo)"))
  end

  test "absence operator" do
    refute_nil(YARP.named_captures("(?~foo)"))
  end

  test "conditional expression with index" do
    refute_nil(YARP.named_captures("(?(1)foo)"))
  end

  test "conditional expression with name" do
    refute_nil(YARP.named_captures("(?(foo)bar)"))
  end

  test "conditional expression with group" do
    refute_nil(YARP.named_captures("(?(<foo>)bar)"))
  end

  test "options on groups" do
    refute_nil(YARP.named_captures("(?imxdau:foo)"))
  end

  test "options on groups with invalid options" do
    assert_nil(YARP.named_captures("(?z:bar)"))
  end

  test "options on groups getting turned off" do
    refute_nil(YARP.named_captures("(?-imx:foo)"))
  end

  test "options on groups some getting turned on some getting turned off" do
    refute_nil(YARP.named_captures("(?im-x:foo)"))
  end

  test "star quantifier" do
    refute_nil(YARP.named_captures("foo*"))
  end

  test "plus quantifier" do
    refute_nil(YARP.named_captures("foo+"))
  end

  test "question mark quantifier" do
    refute_nil(YARP.named_captures("foo?"))
  end

  test "endless range quantifier" do
    refute_nil(YARP.named_captures("foo{1,}"))
  end

  test "beginless range quantifier" do
    refute_nil(YARP.named_captures("foo{,1}"))
  end

  test "range quantifier" do
    refute_nil(YARP.named_captures("foo{1,2}"))
  end

  test "fake range quantifier because of spaces" do
    refute_nil(YARP.named_captures("foo{1, 2}"))
  end
end
