require 'rubygems/test_case'
require 'rubygems/request_set'

class TestGemRequestSetGemDependencyAPI < Gem::TestCase

  def setup
    super

    @GDA = Gem::RequestSet::GemDependencyAPI

    @set = Gem::RequestSet.new

    @vendor_set = Gem::DependencyResolver::VendorSet.new

    @gda = @GDA.new @set, 'gem.deps.rb'
    @gda.instance_variable_set :@vendor_set, @vendor_set
  end

  def test_gem
    @gda.gem 'a'

    assert_equal [dep('a')], @set.dependencies
  end

  def test_gem_group
    @gda.gem 'a', :group => :test

    expected = {
      :test => [['a']],
    }

    assert_equal expected, @gda.dependency_groups

    assert_empty @set.dependencies
  end

  def test_gem_groups
    @gda.gem 'a', :groups => [:test, :development]

    expected = {
      :development => [['a']],
      :test        => [['a']],
    }

    assert_equal expected, @gda.dependency_groups

    assert_empty @set.dependencies
  end

  def test_gem_path
    name, version, directory = vendor_gem

    @gda.gem name, :path => directory

    assert_equal [dep(name)], @set.dependencies

    loaded = @vendor_set.load_spec(name, version, Gem::Platform::RUBY, nil)

    assert_equal "#{name}-#{version}", loaded.full_name
  end

  def test_gem_requirement
    @gda.gem 'a', '~> 1.0'

    assert_equal [dep('a', '~> 1.0')], @set.dependencies
  end

  def test_gem_requirements
    @gda.gem 'b', '~> 1.0', '>= 1.0.2'

    assert_equal [dep('b', '~> 1.0', '>= 1.0.2')], @set.dependencies
  end

  def test_gem_requirements_options
    @gda.gem 'c', :git => 'https://example/c.git'

    assert_equal [dep('c')], @set.dependencies
  end

  def test_gem_deps_file
    assert_equal 'gem.deps.rb', @gda.gem_deps_file

    gda = @GDA.new @set, 'foo/Gemfile'

    assert_equal 'Gemfile', gda.gem_deps_file
  end

  def test_group
    @gda.group :test do
      @gda.gem 'a'
    end

    assert_equal [['a']], @gda.dependency_groups[:test]

    assert_empty @set.dependencies
  end

  def test_group_multiple
    @gda.group :a do
      @gda.gem 'a', :group => :b, :groups => [:c, :d]
    end

    assert_equal [['a']], @gda.dependency_groups[:a]
    assert_equal [['a']], @gda.dependency_groups[:b]
    assert_equal [['a']], @gda.dependency_groups[:c]
    assert_equal [['a']], @gda.dependency_groups[:d]
  end

  def test_load
    Tempfile.open 'gem.deps.rb' do |io|
      io.write <<-GEM_DEPS
gem 'a'

group :test do
  gem 'b'
end
      GEM_DEPS
      io.flush

      gda = @GDA.new @set, io.path

      gda.load

      expected = {
        :test => [['b']],
      }

      assert_equal expected, gda.dependency_groups

      assert_equal [dep('a')], @set.dependencies
    end
  end

  def test_name_typo
    assert_same @GDA, Gem::RequestSet::DepedencyAPI
  end

  def test_platform_mswin
    @gda.platform :mswin do
      @gda.gem 'a'
    end

    assert_empty @set.dependencies
  end

  def test_platform_ruby
    @gda.platform :ruby do
      @gda.gem 'a'
    end

    assert_equal [dep('a')], @set.dependencies
  end

  def test_platforms
    @gda.platforms :ruby do
      @gda.gem 'a'
    end

    assert_equal [dep('a')], @set.dependencies
  end

  def test_ruby
    assert @gda.ruby RUBY_VERSION
  end

  def test_ruby_engine
    assert @gda.ruby RUBY_VERSION,
                     :engine => 'jruby', :engine_version => '1.7.4'
  end

  def test_ruby_mismatch
    e = assert_raises Gem::RubyVersionMismatch do
      @gda.ruby '1.8.0'
    end

    assert_equal "Your Ruby version is #{RUBY_VERSION}, but your gem.deps.rb specified 1.8.0", e.message
  end

end

