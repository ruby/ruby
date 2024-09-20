# frozen_string_literal: true

require_relative "helper"
require "rubygems/dependency"

class TestGemDependency < Gem::TestCase
  def setup
    super

    without_any_upwards_gemfiles
  end

  def test_initialize
    d = dep "pkg", "> 1.0"

    assert_equal "pkg", d.name
    assert_equal req("> 1.0"), d.requirement
  end

  def test_initialize_type_bad
    e = assert_raise ArgumentError do
      Gem::Dependency.new "monkey" => "1.0"
    end

    assert_equal 'dependency name must be a String, was {"monkey"=>"1.0"}',
                 e.message
  end

  def test_initialize_double
    d = dep "pkg", "> 1.0", "< 2.0"
    assert_equal req("> 1.0", "< 2.0"), d.requirement
  end

  def test_initialize_empty
    d = dep "pkg"
    assert_equal req(">= 0"), d.requirement
  end

  def test_initialize_prerelease
    d = dep "d", "1.a"

    assert d.prerelease?

    d = dep "d", "= 1.a"

    assert d.prerelease?
  end

  def test_initialize_type
    assert_equal :runtime, dep("pkg").type
    assert_equal :development, dep("pkg", [], :development).type

    assert_raise ArgumentError do
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

    assert_match d,                  d,             "match self"
    assert_match dep("a", ">= 0"),   d,             "match version exact"
    assert_match dep("a", ">= 0"),   dep("a", "1"), "match version"
    refute_match dep("a"), Object.new

    Gem::Deprecate.skip_during do
      assert_match dep(/a/, ">= 0"),   d,             "match simple regexp"
      assert_match dep(/a|b/, ">= 0"), d,             "match scary regexp"
      refute_match dep(/a/), dep("b")
    end
  end

  def test_equals_tilde_escape
    refute_match dep("a|b"), dep("a", "1")
    Gem::Deprecate.skip_during do
      assert_match dep(/a|b/), dep("a", "1")
    end
  end

  def test_equals_tilde_object
    o = Object.new
    def o.name
      "a"
    end

    def o.version
      "0"
    end

    assert_match dep("a"), o
  end

  def test_equals_tilde_spec
    assert_match dep("a", ">= 0"),   spec("a", "0")
    assert_match dep("a", "1"),      spec("a", "1")
    Gem::Deprecate.skip_during do
      assert_match dep(/a/, ">= 0"),   spec("a", "0")
      assert_match dep(/a|b/, ">= 0"), spec("b", "0")
      refute_match dep(/a/, ">= 0"),   spec("b", "0")
    end
  end

  def test_hash
    d = dep "pkg", "1.0"

    assert_equal d.hash, d.dup.hash
    assert_equal d.dup.hash, d.hash

    refute_equal dep("pkg", "1.0").hash,   dep("pkg", "2.0").hash, "requirement"
    refute_equal dep("pkg", "1.0").hash,   dep("abc", "1.0").hash, "name"
    refute_equal dep("pkg", :development), dep("pkg", :runtime), "type"
  end

  def test_match_eh_name_tuple
    a_dep = dep "a"

    a_tup = Gem::NameTuple.new "a", 1
    b_tup = Gem::NameTuple.new "b", 2
    c_tup = Gem::NameTuple.new "c", "2.a"

    assert a_dep.match? a_tup
    refute a_dep.match? b_tup

    b_dep = dep "b", ">= 3"

    refute b_dep.match? b_tup

    c_dep = dep "c", ">= 1"

    refute c_dep.match? c_tup

    c_dep = dep "c"

    refute c_dep.match? c_tup

    c_dep = dep "c", "2.a"

    assert c_dep.match? c_tup
  end

  def test_match_eh_allow_prerelease
    a_dep = dep "a"

    a_tup = Gem::NameTuple.new "a", 1
    b_tup = Gem::NameTuple.new "b", 2
    c_tup = Gem::NameTuple.new "c", "2.a"

    assert a_dep.match? a_tup, nil, true
    refute a_dep.match? b_tup, nil, true

    b_dep = dep "b", ">= 3"

    refute b_dep.match? b_tup, nil, true

    c_dep = dep "c", ">= 1"

    assert c_dep.match? c_tup, nil, true

    c_dep = dep "c"

    assert c_dep.match? c_tup, nil, true

    c_dep = dep "c", "2.a"

    assert c_dep.match? c_tup, nil, true
  end

  def test_match_eh_specification
    a_dep = dep "a"

    a_spec = util_spec "a", 1
    b_spec = util_spec "b", 2
    c_spec = util_spec "c", "2.a"

    assert a_dep.match? a_spec
    refute a_dep.match? b_spec

    b_dep = dep "b", ">= 3"

    refute b_dep.match? b_spec

    c_dep = dep "c", ">= 1"

    refute c_dep.match? c_spec

    c_dep = dep "c"

    refute c_dep.match? c_spec

    c_dep = dep "c", "2.a"

    assert c_dep.match? c_spec
  end

  def test_matches_spec_eh
    spec = util_spec "b", 2

    refute dep("a")        .matches_spec?(spec), "name mismatch"
    assert dep("b")        .matches_spec?(spec), "name match"
    refute dep("b", "= 1") .matches_spec?(spec), "requirement mismatch"
    assert dep("b", "~> 2").matches_spec?(spec), "requirement match"
  end

  def test_matches_spec_eh_prerelease
    spec = util_spec "b", "2.1.a"

    refute dep("a")          .matches_spec?(spec), "name mismatch"
    assert dep("b")          .matches_spec?(spec), "name match"
    refute dep("b", "= 1")   .matches_spec?(spec), "requirement mismatch"
    assert dep("b", "~> 2")  .matches_spec?(spec), "requirement match"
    assert dep("b", "~> 2.a").matches_spec?(spec), "prerelease requirement"
  end

  def test_merge
    a1 = dep "a", "~> 1.0"
    a2 = dep "a", "= 1.0"

    a3 = a1.merge a2

    assert_equal dep("a", "~> 1.0", "= 1.0"), a3
  end

  def test_merge_default
    a1 = dep "a"
    a2 = dep "a", "1"

    a3 = a1.merge a2

    assert_equal dep("a", "1"), a3
  end

  def test_merge_name_mismatch
    a = dep "a"
    b = dep "b"

    e = assert_raise ArgumentError do
      a.merge b
    end

    assert_equal "a (>= 0) and b (>= 0) have different names",
                 e.message
  end

  def test_merge_other_default
    a1 = dep "a", "1"
    a2 = dep "a"

    a3 = a1.merge a2

    assert_equal dep("a", "1"), a3
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

  def test_specific
    refute dep("a", "> 1").specific?

    assert dep("a", "= 1").specific?
  end

  def test_to_spec
    a_1 = util_spec "a", "1"
    a_2 = util_spec "a", "2"

    a_dep = dep "a", ">= 0"
    install_specs a_1, a_2

    assert_equal a_2, a_dep.to_spec
  end

  def test_to_spec_prerelease
    a_1     = util_spec "a", "1"
    a_1_1_a = util_spec "a", "1.1.a"

    a_dep = dep "a", ">= 0"
    install_specs a_1, a_1_1_a

    assert_equal a_1, a_dep.to_spec

    a_pre_dep = dep "a", ">= 0"
    a_pre_dep.prerelease = true

    assert_equal a_1_1_a, a_pre_dep.to_spec
  end

  def test_to_specs_suggests_other_versions
    a = util_spec "a", "1.0"
    install_specs a

    a_file = File.join a.gem_dir, "lib", "a_file.rb"

    write_file a_file do |io|
      io.puts "# a_file.rb"
    end

    dep = Gem::Dependency.new "a", "= 2.0"

    e = assert_raise Gem::MissingSpecVersionError do
      dep.to_specs
    end

    assert_match "Could not find 'a' (= 2.0) - did find: [a-1.0]", e.message
  end

  def test_to_specs_respects_bundler_version
    b = util_spec "bundler", "2.0.0.pre.1"
    b_1 = util_spec "bundler", "1"
    install_specs b, b_1

    b_file = File.join b.gem_dir, "lib", "bundler", "setup.rb"

    write_file b_file do |io|
      io.puts "# setup.rb"
    end

    dep = Gem::Dependency.new "bundler", ">= 0.a"

    assert_equal [b, b_1], dep.to_specs

    require "rubygems/bundler_version_finder"

    Gem::BundlerVersionFinder.stub(:bundler_version, Gem::Version.new("1")) do
      assert_equal [b_1, b], dep.to_specs
    end

    Gem::BundlerVersionFinder.stub(:bundler_version, Gem::Version.new("2.0.0.pre.1")) do
      assert_equal [b, b_1], dep.to_specs
    end
  end

  def test_to_specs_indicates_total_gem_set_size
    a = util_spec "a", "1.0"
    install_specs a

    a_file = File.join a.gem_dir, "lib", "a_file.rb"

    write_file a_file do |io|
      io.puts "# a_file.rb"
    end

    dep = Gem::Dependency.new "b", "= 2.0"

    e = assert_raise Gem::MissingSpecError do
      dep.to_specs
    end

    assert_match "Could not find 'b' (= 2.0) among 1 total gem(s)", e.message
  end

  def test_to_spec_with_only_prereleases
    a_2_a_1 = util_spec "a", "2.a1"
    a_2_a_2 = util_spec "a", "2.a2"
    install_specs a_2_a_1, a_2_a_2

    a_dep = dep "a", ">= 1"

    assert_equal a_2_a_2, a_dep.to_spec
  end

  def test_identity
    assert_equal dep("a", "= 1").identity, :released
    assert_equal dep("a", "= 1.a").identity, :complete
    assert_equal dep("a", " >= 1.a").identity, :abs_latest
    assert_equal dep("a").identity, :latest
  end
end
