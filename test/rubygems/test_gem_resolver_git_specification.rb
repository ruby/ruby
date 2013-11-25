require 'rubygems/test_case'

class TestGemResolverGitSpecification < Gem::TestCase

  def setup
    super

    @set  = Gem::Resolver::GitSet.new
    @spec = Gem::Specification.new 'a', 1
  end

  def test_equals2
    g_spec_a = Gem::Resolver::GitSpecification.new @set, @spec

    assert_equal g_spec_a, g_spec_a

    spec_b = Gem::Specification.new 'b', 1
    g_spec_b = Gem::Resolver::GitSpecification.new @set, spec_b

    refute_equal g_spec_a, g_spec_b

    g_set = Gem::Resolver::GitSet.new
    g_spec_s = Gem::Resolver::GitSpecification.new g_set, @spec

    refute_equal g_spec_a, g_spec_s

    i_set  = Gem::Resolver::IndexSet.new
    source = Gem::Source.new @gem_repo
    i_spec = Gem::Resolver::IndexSpecification.new(
      i_set, 'a', v(1), source, Gem::Platform::RUBY)

    refute_equal g_spec_a, i_spec
  end

  def test_install
    git_gem 'a', 1

    git_spec = Gem::Resolver::GitSpecification.new @set, @spec

    called = false

    git_spec.install({}) do |installer|
      called = installer
    end

    assert called
  end

end

