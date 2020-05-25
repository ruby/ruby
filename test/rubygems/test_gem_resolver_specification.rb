# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverSpecification < Gem::TestCase
  class TestSpec < Gem::Resolver::Specification
    attr_writer :source
    attr_reader :spec

    def initialize(spec)
      super()

      @spec = spec
    end
  end

  def test_install
    gemhome = "#{@gemhome}2"
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
    end

    a = util_spec 'a', 1

    a_spec = TestSpec.new a
    a_spec.source = Gem::Source.new @gem_repo

    a_spec.install :install_dir => gemhome

    assert_path_exist File.join gemhome, 'gems', a.full_name

    expected = File.join gemhome, 'specifications', a.spec_name

    assert_equal expected, a_spec.spec.loaded_from
  end

  def test_installable_platform_eh
    a = util_spec 'a', 1

    a_spec = TestSpec.new a

    assert a_spec.installable_platform?

    b = util_spec 'a', 1 do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    b_spec = TestSpec.new b

    refute b_spec.installable_platform?
  end

  def test_source
    a = util_spec 'a', 1

    source = Gem::Source.new @gem_repo

    a_spec = TestSpec.new a
    a_spec.source = source

    assert_equal source, a_spec.source
  end
end
