#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/version'

class TestGemDependency < RubyGemTestCase

  def setup
    super

    @pkg1_0 = Gem::Dependency.new 'pkg', ['> 1.0']
    @pkg1_1 = Gem::Dependency.new 'pkg', ['> 1.1']

    @oth1_0 = Gem::Dependency.new 'other', ['> 1.0']

    @r1_0 = Gem::Requirement.new ['> 1.0']
  end

  def dep(name, version)
    Gem::Dependency.new name, version
  end

  def test_initialize
    assert_equal "pkg", @pkg1_0.name
    assert_equal @r1_0, @pkg1_0.version_requirements
  end

  def test_initialize_double
    dep = Gem::Dependency.new("pkg", ["> 1.0", "< 2.0"])

    assert_equal Gem::Requirement.new(["> 1.0", "< 2.0"]),
                 dep.version_requirements
  end

  def test_initialize_empty
    dep = Gem::Dependency.new("pkg", [])
    req = @r1_0

    req.instance_eval do
      @version = ">= 1.0"
      @op = ">="
      @nums = [1,0]
      @requirements = nil
    end

    dep.instance_eval do
      @version_requirement = req
      @version_requirements = nil
    end

    assert_equal Gem::Requirement.new([">= 1.0"]), dep.version_requirements
  end

  def test_initialize_version
    dep = Gem::Dependency.new 'pkg', Gem::Version.new('2')

    assert_equal 'pkg', dep.name

    assert_equal Gem::Requirement.new('= 2'), dep.version_requirements
  end

  def test_initialize_with_type
    dep = Gem::Dependency.new("pkg", [], :development)
    assert_equal(:development, dep.type)
  end

  def test_type_is_runtime_by_default
    assert_equal(:runtime, Gem::Dependency.new("pkg", []).type)
  end

  def test_type_is_restricted
    assert_raises ArgumentError do
      Gem::Dependency.new("pkg", [:sometimes])
    end
  end

  def test_equals2
    assert_equal @pkg1_0, @pkg1_0.dup
    assert_equal @pkg1_0.dup, @pkg1_0

    refute_equal @pkg1_0, @pkg1_1, "requirements different"
    refute_equal @pkg1_1, @pkg1_0, "requirements different"

    refute_equal @pkg1_0, @oth1_0, "names different"
    refute_equal @oth1_0, @pkg1_0, "names different"

    refute_equal @pkg1_0, Object.new
    refute_equal Object.new, @pkg1_0
  end

  def test_equals2_type
    runtime = Gem::Dependency.new("pkg", [])
    development = Gem::Dependency.new("pkg", [], :development)

    refute_equal(runtime, development)
  end

  def test_equals_tilde
    a0   = dep 'a', '0'
    a1   = dep 'a', '1'
    b0   = dep 'b', '0'

    pa0  = dep 'a', '>= 0'
    pa0r = dep(/a/, '>= 0')
    pab0r = dep(/a|b/, '>= 0')

    assert_match a0,    a0, 'match self'
    assert_match pa0,   a0, 'match version exact'
    assert_match pa0,   a1, 'match version'
    assert_match pa0r,  a0, 'match regex simple'
    assert_match pab0r, a0, 'match regex complex'

    refute_match pa0r, b0,         'fail match regex'
    refute_match pa0r, Object.new, 'fail match Object'
  end

  def test_equals_tilde_escape
    a1 = Gem::Dependency.new 'a', '1'

    pab1  = Gem::Dependency.new 'a|b', '>= 1'
    pab1r = Gem::Dependency.new(/a|b/, '>= 1')

    refute_match pab1,  a1, 'escaped'
    assert_match pab1r, a1, 'exact regexp'
  end

  def test_equals_tilde_object
    a0 = Object.new

    def a0.name() 'a' end
    def a0.version() '0' end

    pa0  = Gem::Dependency.new 'a', '>= 0'

    assert_match pa0, a0, 'match version exact'
  end

  def test_equals_tilde_spec
    def spec(name, version)
      Gem::Specification.new do |spec|
        spec.name = name
        spec.version = version
      end
    end

    a0   = spec 'a', '0'
    a1   = spec 'a', '1'
    b0   = spec 'b', '0'

    pa0  = dep 'a', '>= 0'
    pa0r = dep(/a/, '>= 0')
    pab0r = dep(/a|b/, '>= 0')

    assert_match pa0, a0,   'match version exact'
    assert_match pa0, a1,   'match version'

    assert_match pa0r, a0,  'match regex simple'
    assert_match pa0r, a1,  'match regex simple'

    assert_match pab0r, a0, 'match regex complex'
    assert_match pab0r, b0, 'match regex complex'

    refute_match pa0r, b0,         'fail match regex'
    refute_match pa0r, Object.new, 'fail match Object'
  end

  def test_hash
    assert_equal @pkg1_0.hash, @pkg1_0.dup.hash
    assert_equal @pkg1_0.dup.hash, @pkg1_0.hash

    refute_equal @pkg1_0.hash, @pkg1_1.hash, "requirements different"
    refute_equal @pkg1_1.hash, @pkg1_0.hash, "requirements different"

    refute_equal @pkg1_0.hash, @oth1_0.hash, "names different"
    refute_equal @oth1_0.hash, @pkg1_0.hash, "names different"
  end

  def test_hash_type
    runtime = Gem::Dependency.new("pkg", [])
    development = Gem::Dependency.new("pkg", [], :development)

    refute_equal(runtime.hash, development.hash)
  end

end

