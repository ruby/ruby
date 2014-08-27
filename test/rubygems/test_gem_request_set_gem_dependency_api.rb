require 'rubygems/test_case'
require 'rubygems/request_set'

class TestGemRequestSetGemDependencyAPI < Gem::TestCase

  def setup
    super

    @GDA = Gem::RequestSet::GemDependencyAPI

    @set = Gem::RequestSet.new

    @git_set    = Gem::Resolver::GitSet.new
    @vendor_set = Gem::Resolver::VendorSet.new

    @gda = @GDA.new @set, 'gem.deps.rb'
    @gda.instance_variable_set :@git_set,    @git_set
    @gda.instance_variable_set :@vendor_set, @vendor_set
  end

  def with_engine_version name, version
    engine               = RUBY_ENGINE if Object.const_defined? :RUBY_ENGINE
    engine_version_const = "#{Gem.ruby_engine.upcase}_VERSION"
    engine_version       = Object.const_get engine_version_const

    Object.send :remove_const, :RUBY_ENGINE         if engine
    Object.send :remove_const, engine_version_const if name == 'ruby' and
      Object.const_defined? engine_version_const

    new_engine_version_const = "#{name.upcase}_VERSION"
    Object.const_set :RUBY_ENGINE,             name    if name
    Object.const_set new_engine_version_const, version if version

    Gem.instance_variable_set :@ruby_version, Gem::Version.new(version)

    yield

  ensure
    Object.send :remove_const, :RUBY_ENGINE             if name
    Object.send :remove_const, new_engine_version_const if version

    Object.send :remove_const, engine_version_const     if name == 'ruby' and
      Object.const_defined? engine_version_const

    Object.const_set :RUBY_ENGINE,         engine         if engine
    Object.const_set engine_version_const, engine_version unless
      Object.const_defined? engine_version_const

    Gem.send :remove_instance_variable, :@ruby_version if
      Gem.instance_variables.include? :@ruby_version
  end

  def test_gemspec_without_group
    @gda.send :add_dependencies, [:development], [dep('a', '= 1')]

    assert_equal [dep('a', '= 1')], @set.dependencies

    @gda.without_groups << :development

    @gda.send :add_dependencies, [:development], [dep('b', '= 2')]

    assert_equal [dep('a', '= 1')], @set.dependencies
  end

  def test_gem
    @gda.gem 'a'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[a], @gda.requires['a']
  end

  def test_gem_git
    @gda.gem 'a', :git => 'git/a'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git/a master], @git_set.repositories['a']
  end

  def test_gem_git_branch
    @gda.gem 'a', :git => 'git/a', :branch => 'other', :tag => 'v1'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git/a other], @git_set.repositories['a']
  end

  def test_gem_git_gist
    @gda.gem 'a', :gist => 'a'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[https://gist.github.com/a.git master],
                 @git_set.repositories['a']
  end

  def test_gem_git_ref
    @gda.gem 'a', :git => 'git/a', :ref => 'abcd123', :branch => 'other'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git/a abcd123], @git_set.repositories['a']
  end

  def test_gem_git_submodules
    @gda.gem 'a', :git => 'git/a', :submodules => true

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git/a master], @git_set.repositories['a']
    assert_equal %w[git/a], @git_set.need_submodules.keys
  end

  def test_gem_git_tag
    @gda.gem 'a', :git => 'git/a', :tag => 'v1'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git/a v1], @git_set.repositories['a']
  end

  def test_gem_github
    @gda.gem 'a', :github => 'example/repository'

    assert_equal [dep('a')], @set.dependencies

    assert_equal %w[git://github.com/example/repository.git master],
                 @git_set.repositories['a']
  end

  def test_gem_group
    @gda.gem 'a', :group => :test

    assert_equal [dep('a')], @set.dependencies
  end

  def test_gem_group_without
    @gda.without_groups << :test

    @gda.gem 'a', :group => :test

    assert_empty @set.dependencies
  end

  def test_gem_groups
    @gda.gem 'a', :groups => [:test, :development]

    assert_equal [dep('a')], @set.dependencies
  end

  def test_gem_path
    name, version, directory = vendor_gem

    @gda.gem name, :path => directory

    assert_equal [dep(name)], @set.dependencies

    loaded = @vendor_set.load_spec(name, version, Gem::Platform::RUBY, nil)

    assert_equal "#{name}-#{version}", loaded.full_name
  end

  def test_gem_platforms
    win_platform, Gem.win_platform = Gem.win_platform?, false

    with_engine_version 'ruby', '2.0.0' do
      @gda.gem 'a', :platforms => :ruby

      refute_empty @set.dependencies
    end
  ensure
    Gem.win_platform = win_platform
  end

  def test_gem_platforms_bundler_ruby
    win_platform, Gem.win_platform = Gem.win_platform?, false

    with_engine_version 'ruby', '2.0.0' do
      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :ruby

      refute_empty set.dependencies
    end

    with_engine_version 'rbx', '2.0.0' do
      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :ruby

      refute_empty set.dependencies
    end

    with_engine_version 'jruby', '1.7.6' do
      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :ruby

      assert_empty set.dependencies
    end

    Gem.win_platform = true

    with_engine_version 'ruby', '2.0.0' do
      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :ruby

      assert_empty set.dependencies
    end

    Gem.win_platform = win_platform
  end

  def test_gem_platforms_engine
    with_engine_version 'jruby', '1.7.6' do
      @gda.gem 'a', :platforms => :mri

      assert_empty @set.dependencies
    end
  end

  def test_gem_platforms_maglev
    win_platform, Gem.win_platform = Gem.win_platform?, false

    with_engine_version 'maglev', '1.0.0' do
      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :ruby

      refute_empty set.dependencies

      set = Gem::RequestSet.new
      gda = @GDA.new set, 'gem.deps.rb'
      gda.gem 'a', :platforms => :maglev

      refute_empty set.dependencies
    end
  ensure
    Gem.win_platform = win_platform
  end

  def test_gem_platforms_multiple
    win_platform, Gem.win_platform = Gem.win_platform?, false

    with_engine_version 'ruby', '2.0.0' do
      @gda.gem 'a', :platforms => [:mswin, :jruby]

      assert_empty @set.dependencies
    end

  ensure
    Gem.win_platform = win_platform
  end

  def test_gem_platforms_version
    with_engine_version 'ruby', '2.0.0' do
      @gda.gem 'a', :platforms => :ruby_18

      assert_empty @set.dependencies
    end
  end

  def test_gem_platforms_unknown
    e = assert_raises ArgumentError do
      @gda.gem 'a', :platforms => :unknown
    end

    assert_equal 'unknown platform :unknown', e.message
  end

  def test_gem_require
    @gda.gem 'a', :require => %w[b c]
    @gda.gem 'd', :require => 'e'

    assert_equal [dep('a'), dep('d')], @set.dependencies

    assert_equal %w[b c], @gda.requires['a']
    assert_equal %w[e],   @gda.requires['d']
  end

  def test_gem_require_false
    @gda.gem 'a', :require => false

    assert_equal [dep('a')], @set.dependencies

    assert_empty @gda.requires
  end

  def test_gem_require_without_group
    @gda.without_groups << :test

    @gda.gem 'a', :group => :test

    assert_empty @set.dependencies

    assert_empty @gda.requires['a']
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

  def test_gem_source_mismatch
    name, _, directory = vendor_gem

    gda = @GDA.new @set, nil
    gda.gem name

    e = assert_raises ArgumentError do
      gda.gem name, :path => directory
    end

    assert_equal "duplicate source path: #{directory} for gem #{name}",
                 e.message

    gda = @GDA.new @set, nil
    gda.instance_variable_set :@vendor_set, @vendor_set
    gda.gem name, :path => directory

    e = assert_raises ArgumentError do
      gda.gem name
    end

    assert_equal "duplicate source (default) for gem #{name}",
                 e.message
  end

  def test_gem_deps_file
    assert_equal 'gem.deps.rb', @gda.gem_deps_file

    gda = @GDA.new @set, 'foo/Gemfile'

    assert_equal 'Gemfile', gda.gem_deps_file
  end

  def test_gem_group_method
    groups = []

    @gda.group :a do
      groups = @gda.send :gem_group, 'a', :group => :b, :groups => [:c, :d]
    end

    assert_equal [:a, :b, :c, :d], groups.sort_by { |group| group.to_s }
  end

  def test_gemspec
    spec = util_spec 'a', 1, 'b' => 2
    spec.add_development_dependency 'c', 3

    open 'a.gemspec', 'w' do |io|
      io.write spec.to_ruby_for_cache
    end

    @gda.gemspec

    assert_equal [dep('b', '= 2'), dep('c', '=3')], @set.dependencies

    assert_equal %w[a], @gda.requires['a']
  end

  def test_gemspec_bad
    FileUtils.touch 'a.gemspec'

    e = assert_raises ArgumentError do
      capture_io do
        @gda.gemspec
      end
    end

    assert_equal 'invalid gemspec ./a.gemspec', e.message
  end

  def test_gemspec_development_group
    spec = util_spec 'a', 1, 'b' => 2
    spec.add_development_dependency 'c', 3

    open 'a.gemspec', 'w' do |io|
      io.write spec.to_ruby_for_cache
    end

    @gda.without_groups << :other

    @gda.gemspec :development_group => :other

    assert_equal [dep('b', '= 2')], @set.dependencies

    assert_equal %w[a], @gda.requires['a']
  end

  def test_gemspec_multiple
    open 'a.gemspec', 'w' do |io|
      spec = util_spec 'a', 1, 'b' => 2
      io.write spec.to_ruby_for_cache
    end

    open 'b.gemspec', 'w' do |io|
      spec = util_spec 'b', 2, 'c' => 3
      io.write spec.to_ruby_for_cache
    end

    e = assert_raises ArgumentError do
      @gda.gemspec
    end

    assert_equal "found multiple gemspecs at #{@tempdir}, use the name: option to specify the one you want", e.message
  end

  def test_gemspec_name
    open 'a.gemspec', 'w' do |io|
      spec = util_spec 'a', 1, 'b' => 2
      io.write spec.to_ruby_for_cache
    end

    open 'b.gemspec', 'w' do |io|
      spec = util_spec 'b', 2, 'c' => 3
      io.write spec.to_ruby_for_cache
    end

    @gda.gemspec :name => 'b'

    assert_equal [dep('c', '= 3')], @set.dependencies
  end

  def test_gemspec_named
    spec = util_spec 'a', 1, 'b' => 2

    open 'other.gemspec', 'w' do |io|
      io.write spec.to_ruby_for_cache
    end

    @gda.gemspec

    assert_equal [dep('b', '= 2')], @set.dependencies
  end

  def test_gemspec_none
    e = assert_raises ArgumentError do
      @gda.gemspec
    end

    assert_equal "no gemspecs found at #{@tempdir}", e.message
  end

  def test_gemspec_path
    spec = util_spec 'a', 1, 'b' => 2

    FileUtils.mkdir 'other'

    open 'other/a.gemspec', 'w' do |io|
      io.write spec.to_ruby_for_cache
    end

    @gda.gemspec :path => 'other'

    assert_equal [dep('b', '= 2')], @set.dependencies
  end

  def test_git
    @gda.git 'git://example/repo.git' do
      @gda.gem 'a'
      @gda.gem 'b'
    end

    assert_equal [dep('a'), dep('b')], @set.dependencies

    assert_equal %w[git://example/repo.git master], @git_set.repositories['a']
    assert_equal %w[git://example/repo.git master], @git_set.repositories['b']
  end

  def test_group
    @gda.group :test do
      @gda.gem 'a'
    end

    assert_equal [dep('a')], @set.dependencies
  end

  def test_load
    tf = Tempfile.open 'gem.deps.rb' do |io|
      io.write <<-GEM_DEPS
gem 'a'

group :test do
  gem 'b'
end
      GEM_DEPS
      io.flush

      gda = @GDA.new @set, io.path

      gda.load

      assert_equal [dep('a'), dep('b')], @set.dependencies
      io
    end
    tf.close!
  end

  def test_name_typo
    assert_same @GDA, Gem::RequestSet::GemDepedencyAPI
  end

  def test_pin_gem_source
    gda = @GDA.new @set, nil

    gda.send :pin_gem_source, 'a'
    gda.send :pin_gem_source, 'a'

    e = assert_raises ArgumentError do
      gda.send :pin_gem_source, 'a', :path, 'vendor/a'
    end

    assert_equal "duplicate source path: vendor/a for gem a",
                 e.message

    e = assert_raises ArgumentError do
      gda.send :pin_gem_source, 'a', :git, 'git://example/repo.git'
    end

    assert_equal "duplicate source git: git://example/repo.git for gem a",
                 e.message
  end

  def test_platform_mswin
    win_platform, Gem.win_platform = Gem.win_platform?, false

    @gda.platform :mswin do
      @gda.gem 'a'
    end

    assert_empty @set.dependencies

    Gem.win_platform = true

    @gda.platform :mswin do
      @gda.gem 'a'
    end

    refute_empty @set.dependencies
  ensure
    Gem.win_platform = win_platform
  end

  def test_platform_ruby
    win_platform, Gem.win_platform = Gem.win_platform?, false

    @gda.platform :ruby do
      @gda.gem 'a'
    end

    assert_equal [dep('a')], @set.dependencies
  ensure
    Gem.win_platform = win_platform
  end

  def test_platforms
    win_platform, Gem.win_platform = Gem.win_platform?, false

    @gda.platforms :ruby do
      @gda.gem 'a'
    end

    assert_equal [dep('a')], @set.dependencies

    @gda.platforms :mswin do
      @gda.gem 'b'
    end

    assert_equal [dep('a')], @set.dependencies

    Gem.win_platform = true

    @gda.platforms :mswin do
      @gda.gem 'c'
    end

    assert_equal [dep('a'), dep('c')], @set.dependencies

  ensure
    Gem.win_platform = win_platform
  end

  def test_ruby
    assert @gda.ruby RUBY_VERSION
  end

  def test_ruby_engine
    with_engine_version 'jruby', '1.7.6' do
      assert @gda.ruby RUBY_VERSION,
               :engine => 'jruby', :engine_version => '1.7.6'

    end
  end

  def test_ruby_engine_mismatch_engine
    with_engine_version 'ruby', '2.0.0' do
      e = assert_raises Gem::RubyVersionMismatch do
        @gda.ruby RUBY_VERSION, :engine => 'jruby', :engine_version => '1.7.4'
      end

      assert_equal 'Your ruby engine is ruby, but your gem.deps.rb requires jruby',
                   e.message
    end
  end

  def test_ruby_engine_mismatch_version
    with_engine_version 'jruby', '1.7.6' do
      e = assert_raises Gem::RubyVersionMismatch do
        @gda.ruby RUBY_VERSION, :engine => 'jruby', :engine_version => '1.7.4'
      end

      assert_equal 'Your ruby engine version is jruby 1.7.6, but your gem.deps.rb requires jruby 1.7.4',
                   e.message
    end
  end

  def test_ruby_engine_no_engine_version
    e = assert_raises ArgumentError do
      @gda.ruby RUBY_VERSION, :engine => 'jruby'
    end

    assert_equal 'you must specify engine_version along with the ruby engine',
                 e.message
  end

  def test_ruby_mismatch
    e = assert_raises Gem::RubyVersionMismatch do
      @gda.ruby '1.8.0'
    end

    assert_equal "Your Ruby version is #{RUBY_VERSION}, but your gem.deps.rb requires 1.8.0", e.message
  end

  def test_source
    sources = Gem.sources

    @gda.source 'http://first.example'

    assert_equal %w[http://first.example], Gem.sources

    assert_same sources, Gem.sources

    @gda.source 'http://second.example'

    assert_equal %w[http://first.example http://second.example], Gem.sources
  end

  def test_with_engine_version
    version = RUBY_VERSION
    engine  = Gem.ruby_engine

    engine_version_const = "#{Gem.ruby_engine.upcase}_VERSION"
    engine_version       = Object.const_get engine_version_const

    with_engine_version 'other', '1.2.3' do
      assert_equal 'other', Gem.ruby_engine
      assert_equal '1.2.3', OTHER_VERSION

      assert_equal version, RUBY_VERSION if engine
    end

    assert_equal version, RUBY_VERSION
    assert_equal engine,  Gem.ruby_engine

    assert_equal engine_version, Object.const_get(engine_version_const) if
      engine
  end

end

