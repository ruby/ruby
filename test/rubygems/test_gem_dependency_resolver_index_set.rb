require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverIndexSet < Gem::TestCase

  def test_load_spec
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    a_2   = quick_spec 'a', 2
    a_2_p = quick_spec 'a', 2 do |s| s.platform = Gem::Platform.local end

    Gem::Specification.add_specs a_2, a_2_p

    util_setup_spec_fetcher a_2, a_2_p

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::DependencyResolver::IndexSet.new

    spec = set.load_spec 'a', version, Gem::Platform.local, source

    assert_equal a_2_p.full_name, spec.full_name
  end

  def test_load_spec_cached
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    a_2   = quick_spec 'a', 2
    a_2_p = quick_spec 'a', 2 do |s| s.platform = Gem::Platform.local end

    Gem::Specification.add_specs a_2, a_2_p

    util_setup_spec_fetcher a_2, a_2_p

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::DependencyResolver::IndexSet.new

    first = set.load_spec 'a', version, Gem::Platform.local, source

    util_setup_spec_fetcher # clear

    second = set.load_spec 'a', version, Gem::Platform.local, source

    assert_same first, second
  end

end

