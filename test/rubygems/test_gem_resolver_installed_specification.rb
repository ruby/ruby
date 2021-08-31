# frozen_string_literal: true
require_relative 'helper'

class TestGemResolverInstalledSpecification < Gem::TestCase
  def setup
    super

    @set = Gem::Resolver::CurrentSet.new
  end

  def test_initialize
    source_spec = util_spec 'a'

    spec = Gem::Resolver::InstalledSpecification.new @set, source_spec

    assert_equal 'a',                 spec.name
    assert_equal Gem::Version.new(2), spec.version
    assert_equal Gem::Platform::RUBY, spec.platform
  end

  def test_install
    a = util_spec 'a'

    spec = Gem::Resolver::InstalledSpecification.new @set, a

    called = :junk

    spec.install({}) do |installer|
      called = installer
    end

    assert_nil called
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
