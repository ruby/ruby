require 'rubygems/test_case'

class TestGemResolverLockSet < Gem::TestCase

  def setup
    super

    @source      = Gem::Source.new @gem_repo
    @lock_source = Gem::Source::Lock.new @source

    @set = Gem::Resolver::LockSet.new @source
  end

  def test_add
    spec = @set.add 'a', '2', Gem::Platform::RUBY

    assert_equal %w[a-2], @set.specs.map { |t| t.full_name }

    assert_kind_of Gem::Resolver::LockSpecification, spec

    assert_equal @set,                spec.set
    assert_equal 'a',                 spec.name
    assert_equal v(2),                spec.version
    assert_equal Gem::Platform::RUBY, spec.platform
    assert_equal @lock_source,        spec.source
  end

  def test_find_all
    @set.add 'a', '2', Gem::Platform::RUBY
    @set.add 'b', '2', Gem::Platform::RUBY

    found = @set.find_all dep 'a'

    assert_equal %w[a-2], found.map { |s| s.full_name }
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

