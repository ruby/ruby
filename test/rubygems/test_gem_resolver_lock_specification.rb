require 'rubygems/test_case'
require 'rubygems/resolver'

class TestGemResolverLockSpecification < Gem::TestCase

  def setup
    super

    @LS = Gem::Resolver::LockSpecification

    @source = Gem::Source.new @gem_repo
    @set    = Gem::Resolver::LockSet.new [@source]
  end

  def test_initialize
    spec = @LS.new @set, 'a', v(2), @source, Gem::Platform::RUBY

    assert_equal 'a',                 spec.name
    assert_equal v(2),                spec.version
    assert_equal Gem::Platform::RUBY, spec.platform

    assert_equal @source, spec.source
  end

  def test_add_dependency
    l_spec = @LS.new @set, 'a', v(2), @source, Gem::Platform::RUBY

    b_dep = dep('b', '>= 0')

    l_spec.add_dependency b_dep

    assert_equal [b_dep], l_spec.dependencies
  end

  def test_install
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.clear
    end

    spec = @LS.new @set, 'a', v(2), @source, Gem::Platform::RUBY

    called = false

    spec.install({}) do |installer|
      called = installer
    end

    refute_nil called
  end

  def test_install_installed
    spec = @LS.new @set, 'a', v(2), @source, Gem::Platform::RUBY

    FileUtils.touch File.join(@gemhome, 'specifications', spec.spec.spec_name)

    called = false

    spec.install({}) do |installer|
      called = installer
    end

    assert_nil called
  end

  def test_spec
    version = v(2)

    l_spec = @LS.new @set, 'a', version, @source, Gem::Platform::RUBY

    b_dep = dep 'b', '>= 0'
    c_dep = dep 'c', '~> 1'

    l_spec.add_dependency b_dep
    l_spec.add_dependency c_dep

    spec = l_spec.spec

    assert_equal 'a',                 spec.name
    assert_equal version,             spec.version
    assert_equal Gem::Platform::RUBY, spec.platform

    assert_equal [b_dep, c_dep], l_spec.spec.dependencies
  end

  def test_spec_loaded
    real_spec = util_spec 'a', 2
    real_spec.activate

    version = v(2)

    l_spec = @LS.new @set, 'a', version, @source, Gem::Platform::RUBY

    assert_same real_spec, l_spec.spec
  end

end

