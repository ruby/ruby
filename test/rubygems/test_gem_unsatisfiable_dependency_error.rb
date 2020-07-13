# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemUnsatisfiableDependencyError < Gem::TestCase
  def setup
    super

    @a_dep = dep 'a', '~> 1'

    @req = Gem::Resolver::DependencyRequest.new @a_dep, nil

    @e = Gem::UnsatisfiableDependencyError.new @req
  end

  def test_errors
    assert_equal [], @e.errors

    @e.errors << :a

    assert_equal [:a], @e.errors
  end

  def test_name
    assert_equal 'a', @e.name
  end

  def test_version
    assert_equal @a_dep.requirement, @e.version
  end
end
