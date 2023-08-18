# frozen_string_literal: true

require_relative "helper"
require "rubygems/available_set"

class TestGemResolverIndexSpecification < Gem::TestCase
  def test_initialize
    set     = Gem::Resolver::IndexSet.new
    source  = Gem::Source.new @gem_repo
    version = Gem::Version.new "3.0.3"

    spec = Gem::Resolver::IndexSpecification.new(
      set, "rails", version, source, Gem::Platform::RUBY)

    assert_equal "rails",             spec.name
    assert_equal version,             spec.version
    assert_equal Gem::Platform::RUBY, spec.platform

    assert_equal source, spec.source
  end

  def test_initialize_platform
    set     = Gem::Resolver::IndexSet.new
    source  = Gem::Source::Local.new
    version = Gem::Version.new "3.0.3"

    spec = Gem::Resolver::IndexSpecification.new(
      set, "rails", version, source, Gem::Platform.local)

    assert_equal Gem::Platform.local, spec.platform
  end

  def test_install
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    set    = Gem::Resolver::IndexSet.new
    source = Gem::Source.new @gem_repo

    spec = Gem::Resolver::IndexSpecification.new(
      set, "a", v(2), source, Gem::Platform::RUBY)

    called = false

    spec.install({}) do |installer|
      called = installer
    end

    assert_path_exist File.join @gemhome, "specifications", "a-2.gemspec"

    assert_kind_of Gem::Installer, called
  end

  def test_spec
    specs = spec_fetcher do |fetcher|
      fetcher.spec "a", 2
      fetcher.spec "a", 2 do |s|
        s.platform = Gem::Platform.local
      end
    end

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::Resolver::IndexSet.new
    i_spec = Gem::Resolver::IndexSpecification.new \
      set, "a", version, source, Gem::Platform.local

    spec = i_spec.spec

    assert_equal specs["a-2-#{Gem::Platform.local}"].full_name, spec.full_name
  end

  def test_spec_local
    a_2_p = util_spec "a", 2 do |s|
      s.platform = Gem::Platform.local
    end

    Gem::Package.build a_2_p

    source = Gem::Source::Local.new
    set = Gem::Resolver::InstallerSet.new :local
    set.always_install << a_2_p

    i_spec = Gem::Resolver::IndexSpecification.new \
      set, "a", v(2), source, Gem::Platform.local

    spec = i_spec.spec

    assert_equal a_2_p.full_name, spec.full_name
  end
end
