#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/version'

class TestGemRequirement < RubyGemTestCase

  def setup
    super

    @r1_2 = Gem::Requirement.new '= 1.2'
    @r1_3 = Gem::Requirement.new '= 1.3'
  end

  def test_initialize
    r = Gem::Requirement.new '2'
    assert_equal '= 2', r.to_s, 'String'

    r = Gem::Requirement.new %w[2]
    assert_equal '= 2', r.to_s, 'Array of Strings'

    r = Gem::Requirement.new Gem::Version.new('2')
    assert_equal '= 2', r.to_s, 'Gem::Version'
  end

  def test_equals2
    assert_equal @r1_2, @r1_2.dup
    assert_equal @r1_2.dup, @r1_2

    refute_equal @r1_3, @r1_2
    refute_equal @r1_2, @r1_3

    refute_equal Object.new, @r1_2
    refute_equal @r1_2, Object.new
  end

  def test_hash
    assert_equal @r1_2.hash, @r1_2.dup.hash
    assert_equal @r1_2.dup.hash, @r1_2.hash

    refute_equal @r1_2.hash, @r1_3.hash
    refute_equal @r1_3.hash, @r1_2.hash
  end

  # We may get some old gems that have requirements in old formats.
  # We need to be able to handle those old requirements by normalizing
  # them to the latest format.
  def test_normalization
    require 'yaml'
    yamldep = %{--- !ruby/object:Gem::Requirement
      nums:
        - 1
        - 0
        - 4
      op: ">="
      version: ">= 1.0.4"}
    dep = YAML.load(yamldep)
    dep.normalize
    assert_equal ">= 1.0.4", dep.to_s
  end

  def test_parse
    assert_equal ['=', Gem::Version.new(1)], @r1_2.parse('  1')

    assert_equal ['=', Gem::Version.new(1)], @r1_2.parse('= 1')
    assert_equal ['>', Gem::Version.new(1)], @r1_2.parse('> 1')

    assert_equal ['=', Gem::Version.new(0)], @r1_2.parse('=')
    assert_equal ['>', Gem::Version.new(0)], @r1_2.parse('>')

    assert_equal ['=', Gem::Version.new(1)], @r1_2.parse("=\n1")
    assert_equal ['=', Gem::Version.new(0)], @r1_2.parse("=\njunk")

    assert_equal ['=', Gem::Version.new(2)], @r1_2.parse(Gem::Version.new('2'))
  end

  def test_parse_illformed
    e = assert_raises ArgumentError do
      @r1_2.parse(nil)
    end

    assert_equal 'Illformed requirement [nil]', e.message

    e = assert_raises ArgumentError do
      @r1_2.parse('')
    end

    assert_equal 'Illformed requirement [""]', e.message
  end

  def test_satisfied_by_eh_bang_equal
    r1_2 = Gem::Requirement.new '!= 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal true,  r1_2.satisfied_by?(nil)
    assert_equal true,  r1_2.satisfied_by?(v1_1)
    assert_equal false, r1_2.satisfied_by?(v1_2)
    assert_equal true,  r1_2.satisfied_by?(v1_3)
  end

  def test_satisfied_by_eh_blank
    r1_2 = Gem::Requirement.new '1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r1_2.satisfied_by?(nil)
    assert_equal false, r1_2.satisfied_by?(v1_1)
    assert_equal true,  r1_2.satisfied_by?(v1_2)
    assert_equal false, r1_2.satisfied_by?(v1_3)
  end

  def test_satisfied_by_eh_equal
    r1_2 = @r1_2
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r1_2.satisfied_by?(nil)
    assert_equal false, r1_2.satisfied_by?(v1_1)
    assert_equal true,  r1_2.satisfied_by?(v1_2)
    assert_equal false, r1_2.satisfied_by?(v1_3)
  end

  def test_satisfied_by_eh_gt
    r1_2 = Gem::Requirement.new '> 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r1_2.satisfied_by?(v1_1)
    assert_equal false, r1_2.satisfied_by?(v1_2)
    assert_equal true,  r1_2.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r1_2.satisfied_by?(nil)
    end
  end

  def test_satisfied_by_eh_gte
    r1_2 = Gem::Requirement.new '>= 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r1_2.satisfied_by?(v1_1)
    assert_equal true,  r1_2.satisfied_by?(v1_2)
    assert_equal true,  r1_2.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r1_2.satisfied_by?(nil)
    end
  end

  def test_satisfied_by_eh_list
    r = Gem::Requirement.create(['> 1.1', '< 1.3'])
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r.satisfied_by?(v1_1)
    assert_equal true,  r.satisfied_by?(v1_2)
    assert_equal false, r.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r.satisfied_by?(nil)
    end
  end

  def test_satisfied_by_eh_lt
    r1_2 = Gem::Requirement.new '< 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal true,  r1_2.satisfied_by?(v1_1)
    assert_equal false, r1_2.satisfied_by?(v1_2)
    assert_equal false, r1_2.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r1_2.satisfied_by?(nil)
    end
  end

  def test_satisfied_by_eh_lte
    r1_2 = Gem::Requirement.new '<= 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal true,  r1_2.satisfied_by?(v1_1)
    assert_equal true,  r1_2.satisfied_by?(v1_2)
    assert_equal false, r1_2.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r1_2.satisfied_by?(nil)
    end
  end

  def test_satisfied_by_eh_tilde_gt
    r1_2 = Gem::Requirement.new '~> 1.2'
    v1_1 = Gem::Version.new '1.1'
    v1_2 = Gem::Version.new '1.2'
    v1_3 = Gem::Version.new '1.3'

    assert_equal false, r1_2.satisfied_by?(v1_1)
    assert_equal true,  r1_2.satisfied_by?(v1_2)
    assert_equal true,  r1_2.satisfied_by?(v1_3)

    assert_raises NoMethodError do
      assert_equal true,  r1_2.satisfied_by?(nil)
    end
  end

end

