# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverAPISpecification < Gem::TestCase

  def test_initialize
    set = Gem::Resolver::APISet.new
    data = {
      :name     => 'rails',
      :number   => '3.0.3',
      :platform => Gem::Platform.local.to_s,
      :dependencies => [
        ['bundler',  '~> 1.0'],
        ['railties', '= 3.0.3'],
      ],
    }

    spec = Gem::Resolver::APISpecification.new set, data

    assert_equal 'rails',                   spec.name
    assert_equal Gem::Version.new('3.0.3'), spec.version
    assert_equal Gem::Platform.local,       spec.platform

    expected = [
      Gem::Dependency.new('bundler',  '~> 1.0'),
      Gem::Dependency.new('railties', '= 3.0.3'),
    ]

    assert_equal expected, spec.dependencies
  end

  def test_fetch_development_dependencies
    specs = spec_fetcher do |fetcher|
      fetcher.spec 'rails', '3.0.3' do |s|
        s.add_runtime_dependency 'bundler',  '~> 1.0'
        s.add_runtime_dependency 'railties', '= 3.0.3'
        s.add_development_dependency 'a',    '= 1'
      end
    end

    rails = specs['rails-3.0.3']

    repo = @gem_repo + 'api/v1/dependencies'

    set = Gem::Resolver::APISet.new repo

    data = {
      :name     => 'rails',
      :number   => '3.0.3',
      :platform => 'ruby',
      :dependencies => [
        ['bundler',  '~> 1.0'],
        ['railties', '= 3.0.3'],
      ],
    }

    util_setup_spec_fetcher rails

    spec = Gem::Resolver::APISpecification.new set, data

    spec.fetch_development_dependencies

    expected = [
      Gem::Dependency.new('bundler',  '~> 1.0'),
      Gem::Dependency.new('railties', '= 3.0.3'),
      Gem::Dependency.new('a',        '= 1', :development),
    ]

    assert_equal expected, spec.dependencies
  end

  def test_installable_platform_eh
    set = Gem::Resolver::APISet.new
    data = {
      :name     => 'a',
      :number   => '1',
      :platform => 'ruby',
      :dependencies => [],
    }

    a_spec = Gem::Resolver::APISpecification.new set, data

    assert a_spec.installable_platform?

    data = {
      :name     => 'b',
      :number   => '1',
      :platform => 'cpu-other_platform-1',
      :dependencies => [],
    }

    b_spec = Gem::Resolver::APISpecification.new set, data

    refute b_spec.installable_platform?

    data = {
      :name     => 'c',
      :number   => '1',
      :platform => Gem::Platform.local.to_s,
      :dependencies => [],
    }

    c_spec = Gem::Resolver::APISpecification.new set, data

    assert c_spec.installable_platform?
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

  def test_spec_jruby_platform
    spec_fetcher do |fetcher|
      fetcher.gem 'j', 1 do |spec|
        spec.platform = 'jruby'
      end
    end

    dep_uri = URI(@gem_repo) + 'api/v1/dependencies'
    set = Gem::Resolver::APISet.new dep_uri
    data = {
      :name         => 'j',
      :number       => '1',
      :platform     => 'jruby',
      :dependencies => [],
    }

    api_spec = Gem::Resolver::APISpecification.new set, data

    spec = api_spec.spec

    assert_kind_of Gem::Specification, spec
    assert_equal 'j-1-java', spec.full_name
  end

end
