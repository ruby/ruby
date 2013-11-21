require 'rubygems/test_case'

class TestGemResolverAPISpecification < Gem::TestCase

  def test_initialize
    set = Gem::Resolver::APISet.new
    data = {
      :name     => 'rails',
      :number   => '3.0.3',
      :platform => 'ruby',
      :dependencies => [
        ['bundler',  '~> 1.0'],
        ['railties', '= 3.0.3'],
      ],
    }

    spec = Gem::Resolver::APISpecification.new set, data

    assert_equal 'rails',                   spec.name
    assert_equal Gem::Version.new('3.0.3'), spec.version
    assert_equal Gem::Platform::RUBY,       spec.platform

    expected = [
      Gem::Dependency.new('bundler',  '~> 1.0'),
      Gem::Dependency.new('railties', '= 3.0.3'),
    ]

    assert_equal expected, spec.dependencies
  end

  def test_source
    set = Gem::Resolver::APISet.new
    data = {
      :name         => 'a',
      :number       => '1',
      :platform     => 'ruby',
      :dependencies => [],
    }

    api_spec = Gem::Resolver::APISpecification.new set, data

    assert_equal set.source, api_spec.source
  end

  def test_spec
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    dep_uri = URI(@gem_repo) + 'api/v1/dependencies'
    set = Gem::Resolver::APISet.new dep_uri
    data = {
      :name         => 'a',
      :number       => '1',
      :platform     => 'ruby',
      :dependencies => [],
    }

    api_spec = Gem::Resolver::APISpecification.new set, data

    spec = api_spec.spec

    assert_kind_of Gem::Specification, spec
    assert_equal 'a-1', spec.full_name
  end

end

