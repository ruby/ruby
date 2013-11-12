require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverInstalledSpecification < Gem::TestCase

  def test_initialize
    set     = Gem::DependencyResolver::CurrentSet.new

    source_spec = util_spec 'a'

    spec = Gem::DependencyResolver::InstalledSpecification.new set, source_spec

    assert_equal 'a',                 spec.name
    assert_equal Gem::Version.new(2), spec.version
    assert_equal Gem::Platform::RUBY, spec.platform
  end

end

