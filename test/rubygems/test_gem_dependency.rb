######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/dependency'

class TestGemDependency < RubyGemTestCase
  def test_initialize
    d = dep "pkg", "> 1.0"

    assert_equal "pkg", d.name
    assert_equal req("> 1.0"), d.requirement
  end

  def test_initialize_double
    d = dep "pkg", "> 1.0", "< 2.0"
    assert_equal req("> 1.0", "< 2.0"), d.requirement
  end

  def test_initialize_empty
    d = dep "pkg"
    assert_equal req(">= 0"), d.requirement
  end

  def test_initialize_type
    assert_equal :runtime, dep("pkg").type
    assert_equal :development, dep("pkg", [], :development).type

    assert_raises ArgumentError do
      dep "pkg", :sometimes
    end
  end

  def test_initialize_version
    d = dep "pkg", v("2")
    assert_equal req("= 2"), d.requirement
  end

  def test_equals2
    o  = dep "other"
    d  = dep "pkg", "> 1.0"
    d1 = dep "pkg", "> 1.1"

    assert_equal d, d.dup
    assert_equal d.dup, d

    refute_equal d, d1
    refute_equal d1, d

    refute_equal d, o
    refute_equal o, d

    refute_equal d, Object.new
    refute_equal Object.new, d
  end

  def test_equals2_type
    refute_equal dep("pkg", :runtime), dep("pkg", :development)
  end

  def test_equals_tilde
    d = dep "a", "0"

    assert_match d,                  d,             "matche self"
    assert_match dep("a", ">= 0"),   d,             "match version exact"
    assert_match dep("a", ">= 0"),   dep("a", "1"), "match version"
    assert_match dep(/a/, ">= 0"),   d,             "match simple regexp"
    assert_match dep(/a|b/, ">= 0"), d,             "match scary regexp"

    refute_match dep(/a/), dep("b")
    refute_match dep("a"), Object.new
  end

  def test_equals_tilde_escape
    refute_match dep("a|b"), dep("a", "1")
    assert_match dep(/a|b/), dep("a", "1")
  end

  def test_equals_tilde_object
    o = Object.new
    def o.name    ; 'a' end
    def o.version ; '0' end

    assert_match dep("a"), o
  end

  def test_equals_tilde_spec
    assert_match dep("a", ">= 0"),   spec("a", "0")
    assert_match dep("a", "1"),      spec("a", "1")
    assert_match dep(/a/, ">= 0"),   spec("a", "0")
    assert_match dep(/a|b/, ">= 0"), spec("b", "0")
    refute_match dep(/a/, ">= 0"),   spec("b", "0")
  end

  def test_hash
    d = dep "pkg", "1.0"

    assert_equal d.hash, d.dup.hash
    assert_equal d.dup.hash, d.hash

    refute_equal dep("pkg", "1.0").hash,   dep("pkg", "2.0").hash, "requirement"
    refute_equal dep("pkg", "1.0").hash,   dep("abc", "1.0").hash, "name"
    refute_equal dep("pkg", :development), dep("pkg", :runtime), "type"
  end

  def test_prerelease_eh
    d = dep "pkg", "= 1"

    refute d.prerelease?

    d.prerelease = true

    assert d.prerelease?

    d = dep "pkg", "= 1.a"

    assert d.prerelease?

    d.prerelease = false

    assert d.prerelease?

    d = dep "pkg", "> 1.a", "> 2"

    assert d.prerelease?
  end
end

