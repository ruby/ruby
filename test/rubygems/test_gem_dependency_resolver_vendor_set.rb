require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverVendorSet < Gem::TestCase

  def setup
    super

    @set = Gem::DependencyResolver::VendorSet.new
  end

  def test_add_vendor_gem
    name, version, directory = vendor_gem

    @set.add_vendor_gem name, directory

    spec = @set.load_spec name, version, Gem::Platform::RUBY, nil

    assert_equal "#{name}-#{version}", spec.full_name
  end

  def test_find_all
    name, version, directory = vendor_gem

    @set.add_vendor_gem name, directory

    dependency = dep 'a', '~> 1'

    req = Gem::DependencyResolver::DependencyRequest.new dependency, nil

    found = @set.find_all req

    spec = @set.load_spec name, version, Gem::Platform::RUBY, nil

    expected = [
      Gem::DependencyResolver::VendorSpecification.new(@set, spec, nil)
    ]

    assert_equal expected, found
  end

  def test_load_spec
    assert_raises KeyError do
      @set.load_spec 'a', v(1), Gem::Platform::RUBY, nil
    end
  end

end

