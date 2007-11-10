#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
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

  def test_equals2
    assert_equal @pkg1_0, @pkg1_0.dup
    assert_equal @pkg1_0.dup, @pkg1_0

    assert_not_equal @pkg1_0, @pkg1_1, "requirements different"
    assert_not_equal @pkg1_1, @pkg1_0, "requirements different"

    assert_not_equal @pkg1_0, @oth1_0, "names different"
    assert_not_equal @oth1_0, @pkg1_0, "names different"

    assert_not_equal @pkg1_0, Object.new
    assert_not_equal Object.new, @pkg1_0
  end

  def test_hash
    assert_equal @pkg1_0.hash, @pkg1_0.dup.hash
    assert_equal @pkg1_0.dup.hash, @pkg1_0.hash

    assert_not_equal @pkg1_0.hash, @pkg1_1.hash, "requirements different"
    assert_not_equal @pkg1_1.hash, @pkg1_0.hash, "requirements different"

    assert_not_equal @pkg1_0.hash, @oth1_0.hash, "names different"
    assert_not_equal @oth1_0.hash, @pkg1_0.hash, "names different"
  end

end

