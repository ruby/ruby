require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverVendorSpecification < Gem::TestCase

  def setup
    super

    @set  = Gem::DependencyResolver::VendorSet.new
    @spec = Gem::Specification.new 'a', 1
  end

  def test_equals2
    v_spec_a = Gem::DependencyResolver::VendorSpecification.new @set, @spec

    assert_equal v_spec_a, v_spec_a

    spec_b = Gem::Specification.new 'b', 1
    v_spec_b = Gem::DependencyResolver::VendorSpecification.new @set, spec_b

    refute_equal v_spec_a, v_spec_b

    v_set = Gem::DependencyResolver::VendorSet.new
    v_spec_s = Gem::DependencyResolver::VendorSpecification.new v_set, @spec

    refute_equal v_spec_a, v_spec_s

    i_set  = Gem::DependencyResolver::IndexSet.new
    source = Gem::Source.new @gem_repo
    i_spec = Gem::DependencyResolver::IndexSpecification.new(
      i_set, 'a', v(1), source, Gem::Platform::RUBY)

    refute_equal v_spec_a, i_spec
  end

  def test_dependencies
    @spec.add_dependency 'b'
    @spec.add_dependency 'c'

    v_spec = Gem::DependencyResolver::VendorSpecification.new @set, @spec

    assert_equal [dep('b'), dep('c')], v_spec.dependencies
  end

  def test_full_name
    v_spec = Gem::DependencyResolver::VendorSpecification.new @set, @spec

    assert_equal 'a-1', v_spec.full_name
  end

  def test_name
    v_spec = Gem::DependencyResolver::VendorSpecification.new @set, @spec

    assert_equal 'a', v_spec.name
  end

  def test_platform
    v_spec = Gem::DependencyResolver::VendorSpecification.new @set, @spec

    assert_equal Gem::Platform::RUBY, v_spec.platform
  end

  def test_version
    spec = Gem::Specification.new 'a', 1

    v_spec = Gem::DependencyResolver::VendorSpecification.new @set, spec

    assert_equal v(1), v_spec.version
  end

end

