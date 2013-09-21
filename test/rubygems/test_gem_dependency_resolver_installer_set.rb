require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverInstallerSet < Gem::TestCase

  def test_load_spec
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    a_2   = quick_spec 'a', 2
    a_2_p = quick_spec 'a', 2 do |s| s.platform = Gem::Platform.local end

    Gem::Specification.add_specs a_2, a_2_p

    util_setup_spec_fetcher a_2, a_2_p

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::DependencyResolver::InstallerSet.new :remote

    spec = set.load_spec 'a', version, Gem::Platform.local, source

    assert_equal a_2_p.full_name, spec.full_name
  end

end

