# frozen_string_literal: true
require 'rubygems/test_case'
require "rubygems/requirement"

class TestGemRequirement < Gem::TestCase

  def test_concat
    r = req '>= 1'

    r.concat ['< 2']

    assert_equal [['>=', v(1)], ['<', v(2)]], r.requirements
  end

  def test_equals2
    r = req "= 1.2"
    assert_equal r, r.dup
    assert_equal r.dup, r

    refute_requirement_equal "= 1.2", "= 1.3"
    refute_requirement_equal "= 1.3", "= 1.2"

    refute_requirement_equal "~> 1.3", "~> 1.3.0"
    refute_requirement_equal "~> 1.3.0", "~> 1.3"

    assert_requirement_equal ["> 2", "~> 1.3"], ["> 2.0", "~> 1.3"]
    assert_requirement_equal ["> 2.0", "~> 1.3"], ["> 2", "~> 1.3"]

    refute_equal Object.new, req("= 1.2")
    refute_equal req("= 1.2"), Object.new
  end

  def test_initialize
    assert_requirement_equal "= 2", "2"
    assert_requirement_equal "= 2", ["2"]
    assert_requirement_equal "= 2", v(2)
    assert_requirement_equal "2.0", "2"
  end

  def test_create
    assert_equal req("= 1"), Gem::Requirement.create("= 1")
    assert_equal req(">= 1.2", "<= 1.3"), Gem::Requirement.create([">= 1.2", "<= 1.3"])
    assert_equal req(">= 1.2", "<= 1.3"), Gem::Requirement.create(">= 1.2", "<= 1.3")
  end

  def test_empty_requirements_is_none
    r = Gem::Requirement.new
    assert_equal true, r.none?
  end

  def test_explicit_default_is_none
    r = Gem::Requirement.new ">= 0"
    assert_equal true, r.none?
  end

  def test_basic_non_none
    r = Gem::Requirement.new "= 1"
    assert_equal false, r.none?
  end

  def test_for_lockfile
    assert_equal ' (~> 1.0)', req('~> 1.0').for_lockfile

    assert_equal ' (~> 1.0, >= 1.0.1)', req('>= 1.0.1', '~> 1.0').for_lockfile

    duped = req '= 1.0'
    duped.requirements << ['=', v('1.0')]

    assert_equal ' (= 1.0)', duped.for_lockfile

    assert_nil Gem::Requirement.default.for_lockfile
  end

  def test_parse
    assert_equal ['=', Gem::Version.new(1)], Gem::Requirement.parse('  1')
    assert_equal ['=', Gem::Version.new(1)], Gem::Requirement.parse('= 1')
    assert_equal ['>', Gem::Version.new(1)], Gem::Requirement.parse('> 1')
    assert_equal ['=', Gem::Version.new(1)], Gem::Requirement.parse("=\n1")
    assert_equal ['=', Gem::Version.new(1)], Gem::Requirement.parse('1.0')

    assert_equal ['=', Gem::Version.new(2)],
      Gem::Requirement.parse(Gem::Version.new('2'))
  end

  def test_parse_bad
    [
      nil,
      '',
      '! 1',
      '= junk',
      '1..2',
    ].each do |bad|
      e = assert_raises Gem::Requirement::BadRequirementError do
        Gem::Requirement.parse bad
      end

      assert_equal "Illformed requirement [#{bad.inspect}]", e.message
    end

    assert_equal Gem::Requirement::BadRequirementError.superclass, ArgumentError
  end

  def test_prerelease_eh
    r = req '= 1'

    refute r.prerelease?

    r = req '= 1.a'

    assert r.prerelease?

    r = req '> 1.a', '< 2'

    assert r.prerelease?
  end

  def test_satisfied_by_eh_bang_equal
    r = req '!= 1.2'

    assert_satisfied_by "1.1", r
    refute_satisfied_by "1.2", r
    assert_satisfied_by "1.3", r

    assert_raises ArgumentError do
      assert_satisfied_by nil, r
    end
  end

  def test_satisfied_by_eh_blank
    r = req "1.2"

    refute_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    refute_satisfied_by "1.3", r

    assert_raises ArgumentError do
      assert_satisfied_by nil, r
    end
  end

  def test_satisfied_by_eh_equal
    r = req "= 1.2"

    refute_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    refute_satisfied_by "1.3", r

    assert_raises ArgumentError do
      assert_satisfied_by nil, r
    end
  end

  def test_satisfied_by_eh_gt
    r = req "> 1.2"

    refute_satisfied_by "1.1", r
    refute_satisfied_by "1.2", r
    assert_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_gte
    r = req ">= 1.2"

    refute_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    assert_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_list
    r = req "> 1.1", "< 1.3"

    refute_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    refute_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_lt
    r = req "< 1.2"

    assert_satisfied_by "1.1", r
    refute_satisfied_by "1.2", r
    refute_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_lte
    r = req "<= 1.2"

    assert_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    refute_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_tilde_gt
    r = req "~> 1.2"

    refute_satisfied_by "1.1", r
    assert_satisfied_by "1.2", r
    assert_satisfied_by "1.3", r

    assert_raises ArgumentError do
      r.satisfied_by? nil
    end
  end

  def test_satisfied_by_eh_tilde_gt_v0
    r = req "~> 0.0.1"

    refute_satisfied_by "0.1.1", r
    assert_satisfied_by "0.0.2", r
    assert_satisfied_by "0.0.1", r
  end

  def test_satisfied_by_eh_good
    assert_satisfied_by "0.2.33",      "= 0.2.33"
    assert_satisfied_by "0.2.34",      "> 0.2.33"
    assert_satisfied_by "1.0",         "= 1.0"
    assert_satisfied_by "1.0.0",       "= 1.0"
    assert_satisfied_by "1.0",         "= 1.0.0"
    assert_satisfied_by "1.0",         "1.0"
    assert_satisfied_by "1.8.2",       "> 1.8.0"
    assert_satisfied_by "1.112",       "> 1.111"
    assert_satisfied_by "0.2",         "> 0.0.0"
    assert_satisfied_by "0.0.0.0.0.2", "> 0.0.0"
    assert_satisfied_by "0.0.1.0",     "> 0.0.0.1"
    assert_satisfied_by "10.3.2",      "> 9.3.2"
    assert_satisfied_by "1.0.0.0",     "= 1.0"
    assert_satisfied_by "10.3.2",      "!= 9.3.4"
    assert_satisfied_by "10.3.2",      "> 9.3.2"
    assert_satisfied_by "10.3.2",      "> 9.3.2"
    assert_satisfied_by " 9.3.2",      ">= 9.3.2"
    assert_satisfied_by "9.3.2 ",      ">= 9.3.2"
    assert_satisfied_by "",            "= 0"
    assert_satisfied_by "",            "< 0.1"
    assert_satisfied_by "  ",          "< 0.1 "
    assert_satisfied_by "",            " <  0.1"
    assert_satisfied_by "  ",          "> 0.a "
    assert_satisfied_by "",            " >  0.a"
    assert_satisfied_by "3.1",         "< 3.2.rc1"

    assert_satisfied_by "3.2.0",       "> 3.2.0.rc1"
    assert_satisfied_by "3.2.0.rc2",   "> 3.2.0.rc1"

    assert_satisfied_by "3.0.rc2",     "< 3.0"
    assert_satisfied_by "3.0.rc2",     "< 3.0.0"
    assert_satisfied_by "3.0.rc2",     "< 3.0.1"

    assert_satisfied_by "3.0.rc2",     "> 0"

    assert_satisfied_by "5.0.0.rc2",   "~> 5.a"
    refute_satisfied_by "5.0.0.rc2",   "~> 5.x"

    assert_satisfied_by "5.0.0",       "~> 5.a"
    assert_satisfied_by "5.0.0",       "~> 5.x"
  end

  def test_illformed_requirements
    [ ">>> 1.3.5", "> blah" ].each do |rq|
      assert_raises Gem::Requirement::BadRequirementError, "req [#{rq}] should fail" do
        Gem::Requirement.new rq
      end
    end
  end

  def test_satisfied_by_eh_non_versions
    assert_raises ArgumentError do
      req(">= 0").satisfied_by? Object.new
    end

    assert_raises ArgumentError do
      req(">= 0").satisfied_by? Gem::Requirement.default
    end
  end

  def test_satisfied_by_eh_boxed
    refute_satisfied_by "1.3",     "~> 1.4"
    assert_satisfied_by "1.4",     "~> 1.4"
    assert_satisfied_by "1.5",     "~> 1.4"
    refute_satisfied_by "2.0",     "~> 1.4"

    refute_satisfied_by "1.3",     "~> 1.4.4"
    refute_satisfied_by "1.4",     "~> 1.4.4"
    assert_satisfied_by "1.4.4",   "~> 1.4.4"
    assert_satisfied_by "1.4.5",   "~> 1.4.4"
    refute_satisfied_by "1.5",     "~> 1.4.4"
    refute_satisfied_by "2.0",     "~> 1.4.4"

    refute_satisfied_by "1.1.pre", "~> 1.0.0"
    refute_satisfied_by "1.1.pre", "~> 1.1"
    refute_satisfied_by "2.0.a",   "~> 1.0"
    refute_satisfied_by "2.0.a",   "~> 2.0"

    refute_satisfied_by "0.9",     "~> 1"
    assert_satisfied_by "1.0",     "~> 1"
    assert_satisfied_by "1.1",     "~> 1"
    refute_satisfied_by "2.0",     "~> 1"
  end

  def test_satisfied_by_eh_multiple
    req = [">= 1.4", "<= 1.6", "!= 1.5"]

    refute_satisfied_by "1.3", req
    assert_satisfied_by "1.4", req
    refute_satisfied_by "1.5", req
    assert_satisfied_by "1.6", req
    refute_satisfied_by "1.7", req
    refute_satisfied_by "2.0", req
  end

  def test_satisfied_by_boxed
    refute_satisfied_by "1.3",   "~> 1.4"
    assert_satisfied_by "1.4",   "~> 1.4"
    assert_satisfied_by "1.4.0", "~> 1.4"
    assert_satisfied_by "1.5",   "~> 1.4"
    refute_satisfied_by "2.0",   "~> 1.4"

    refute_satisfied_by "1.3",   "~> 1.4.4"
    refute_satisfied_by "1.4",   "~> 1.4.4"
    assert_satisfied_by "1.4.4", "~> 1.4.4"
    assert_satisfied_by "1.4.5", "~> 1.4.4"
    refute_satisfied_by "1.5",   "~> 1.4.4"
    refute_satisfied_by "2.0",   "~> 1.4.4"
  end

  def test_satisfied_by_explicitly_bounded
    req = [">= 1.4.4", "< 1.5"]

    assert_satisfied_by "1.4.5",     req
    assert_satisfied_by "1.5.0.rc1", req
    refute_satisfied_by "1.5.0",     req

    req = [">= 1.4.4", "< 1.5.a"]

    assert_satisfied_by "1.4.5",     req
    refute_satisfied_by "1.5.0.rc1", req
    refute_satisfied_by "1.5.0",     req
  end

  def test_specific
    refute req('> 1') .specific?
    refute req('>= 1').specific?

    assert req('!= 1').specific?
    assert req('< 1') .specific?
    assert req('<= 1').specific?
    assert req('= 1') .specific?
    assert req('~> 1').specific?

    assert req('> 1', '> 2').specific? # GIGO
  end

  def test_bad
    refute_satisfied_by "",            "> 0.1"
    refute_satisfied_by "1.2.3",       "!= 1.2.3"
    refute_satisfied_by "1.2.003.0.0", "!= 1.02.3"
    refute_satisfied_by "4.5.6",       "< 1.2.3"
    refute_satisfied_by "1.0",         "> 1.1"
    refute_satisfied_by "",            "= 0.1"
    refute_satisfied_by "1.1.1",       "> 1.1.1"
    refute_satisfied_by "1.2",         "= 1.1"
    refute_satisfied_by "1.40",        "= 1.1"
    refute_satisfied_by "1.3",         "= 1.40"
    refute_satisfied_by "9.3.3",       "<= 9.3.2"
    refute_satisfied_by "9.3.1",       ">= 9.3.2"
    refute_satisfied_by "9.3.03",      "<= 9.3.2"
    refute_satisfied_by "1.0.0.1",     "= 1.0"
  end

  def test_hash_with_multiple_versions
    r1 = req('1.0', '2.0')
    r2 = req('2.0', '1.0')
    assert_equal r1.hash, r2.hash

    r1 = req('1.0', '2.0').tap { |r| r.concat(['3.0']) }
    r2 = req('3.0', '1.0').tap { |r| r.concat(['2.0']) }
    assert_equal r1.hash, r2.hash
  end

  # Assert that two requirements are equal. Handles Gem::Requirements,
  # strings, arrays, numbers, and versions.

  def assert_requirement_equal(expected, actual)
    assert_equal req(expected), req(actual)
  end

  # Assert that +version+ satisfies +requirement+.

  def assert_satisfied_by(version, requirement)
    assert req(requirement).satisfied_by?(v(version)),
      "#{requirement} is satisfied by #{version}"
  end

  # Refute the assumption that two requirements are equal.

  def refute_requirement_equal(unexpected, actual)
    refute_equal req(unexpected), req(actual)
  end

  # Refute the assumption that +version+ satisfies +requirement+.

  def refute_satisfied_by(version, requirement)
    refute req(requirement).satisfied_by?(v(version)),
      "#{requirement} is not satisfied by #{version}"
  end

end
