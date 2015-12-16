# frozen_string_literal: false
require 'rubygems/test_case'

class TestGemResolverLockSet < Gem::TestCase

  def setup
    super

    @sources     = [Gem::Source.new(@gem_repo)]
    @lock_source = Gem::Source::Lock.new @sources.first

    @set = Gem::Resolver::LockSet.new @sources
  end

  def test_add
    specs = @set.add 'a', '2', Gem::Platform::RUBY
    spec = specs.first

    assert_equal %w[a-2], @set.specs.map { |t| t.full_name }

    assert_kind_of Gem::Resolver::LockSpecification, spec

    assert_equal @set,                spec.set
    assert_equal 'a',                 spec.name
    assert_equal v(2),                spec.version
    assert_equal Gem::Platform::RUBY, spec.platform
    assert_equal @lock_source,        spec.source
  end

  def test_find_all
    @set.add 'a', '1.a', Gem::Platform::RUBY
    @set.add 'a', '2',   Gem::Platform::RUBY
    @set.add 'b', '2',   Gem::Platform::RUBY

    found = @set.find_all dep 'a'

    assert_equal %w[a-2], found.map { |s| s.full_name }

    found = @set.find_all dep 'a', '>= 0.a'

    assert_equal %w[a-1.a a-2], found.map { |s| s.full_name }
  end

  def test_load_spec
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
    end

    version = v(2)
    @set.add 'a', version, Gem::Platform::RUBY

    loaded = @set.load_spec 'a', version, Gem::Platform::RUBY, nil

    assert_kind_of Gem::Specification, loaded

    assert_equal 'a-2', loaded.full_name
  end

  def test_prefetch
    assert_respond_to @set, :prefetch
  end

end

