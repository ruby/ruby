# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/available_set'

class TestGemResolverLocalSpecification < Gem::TestCase

  def setup
    super

    @set = Gem::AvailableSet.new
  end

  def test_install
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    source = Gem::Source::SpecificFile.new 'gems/a-2.gem'

    spec = Gem::Resolver::LocalSpecification.new @set, specs['a-2'], source

    called = false

    spec.install({}) do |installer|
      called = installer
    end

    assert_path_exists File.join @gemhome, 'specifications', 'a-2.gemspec'

    assert_kind_of Gem::Installer, called
  end

  def test_installable_platform_eh
    b, b_gem = util_gem 'a', 1 do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    source = Gem::Source::SpecificFile.new b_gem

    b_spec = Gem::Resolver::InstalledSpecification.new @set, b, source

    assert b_spec.installable_platform?
  end

end
