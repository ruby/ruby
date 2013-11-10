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

  def test_add_vendor_gem_missing
    name, _, directory = vendor_gem

    FileUtils.rm_r directory

    e = assert_raises Gem::GemNotFoundException do
      @set.add_vendor_gem name, directory
    end

    assert_equal "unable to find #{directory}/#{name}.gemspec for gem #{name}",
                 e.message
  end

  def test_find_all
    name, version, directory = vendor_gem

    @set.add_vendor_gem name, directory

    dependency = dep 'a', '~> 1'

    req = Gem::DependencyResolver::DependencyRequest.new dependency, nil

    found = @set.find_all req

    spec = @set.load_spec name, version, Gem::Platform::RUBY, nil

    source = Gem::Source::Vendor.new directory

    expected = [
      Gem::DependencyResolver::VendorSpecification.new(@set, spec, source)
    ]

    assert_equal expected, found
  end

  def test_load_spec
    error = Object.const_defined?(:KeyError) ? KeyError : IndexError

    assert_raises error do
      @set.load_spec 'a', v(1), Gem::Platform::RUBY, nil
    end
  end

end

