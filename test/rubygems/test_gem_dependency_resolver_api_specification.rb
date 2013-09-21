require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverAPISpecification < Gem::TestCase

  def test_initialize
    set = Gem::DependencyResolver::APISet.new
    data = {
      :name     => 'rails',
      :number   => '3.0.3',
      :platform => 'ruby',
      :dependencies => [
        ['bundler',  '~> 1.0'],
        ['railties', '= 3.0.3'],
      ],
    }

    spec = Gem::DependencyResolver::APISpecification.new set, data

    assert_equal 'rails',                   spec.name
    assert_equal Gem::Version.new('3.0.3'), spec.version
    assert_equal Gem::Platform::RUBY,       spec.platform

    expected = [
      Gem::Dependency.new('bundler',  '~> 1.0'),
      Gem::Dependency.new('railties', '= 3.0.3'),
    ]

    assert_equal expected, spec.dependencies
  end

end

