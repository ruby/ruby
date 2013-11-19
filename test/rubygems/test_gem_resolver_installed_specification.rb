require 'rubygems/test_case'

class TestGemResolverInstalledSpecification < Gem::TestCase

  def test_initialize
    set     = Gem::Resolver::CurrentSet.new

    source_spec = util_spec 'a'

    spec = Gem::Resolver::InstalledSpecification.new set, source_spec

    assert_equal 'a',                 spec.name
    assert_equal Gem::Version.new(2), spec.version
    assert_equal Gem::Platform::RUBY, spec.platform
  end

end

