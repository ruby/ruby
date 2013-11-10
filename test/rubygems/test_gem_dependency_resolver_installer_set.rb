require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverInstallerSet < Gem::TestCase

  def test_load_spec
    a_2_p = nil

    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
      a_2_p = fetcher.spec 'a', 2 do |s| s.platform = Gem::Platform.local end
    end

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::DependencyResolver::InstallerSet.new :remote

    spec = set.load_spec 'a', version, Gem::Platform.local, source

    assert_equal a_2_p.full_name, spec.full_name
  end

end

