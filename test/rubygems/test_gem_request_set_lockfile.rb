# frozen_string_literal: false
require 'rubygems/test_case'
require 'rubygems/request_set'
require 'rubygems/request_set/lockfile'

class TestGemRequestSetLockfile < Gem::TestCase

  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    util_set_arch 'i686-darwin8.10.1'

    @set = Gem::RequestSet.new

    @git_set    = Gem::Resolver::GitSet.new
    @vendor_set = Gem::Resolver::VendorSet.new

    @set.instance_variable_set :@git_set,    @git_set
    @set.instance_variable_set :@vendor_set, @vendor_set

    @gem_deps_file = 'gem.deps.rb'

  end

  def lockfile
    Gem::RequestSet::Lockfile.build @set, @gem_deps_file
  end

  def write_lockfile lockfile
    @lock_file = File.expand_path "#{@gem_deps_file}.lock"

    open @lock_file, 'w' do |io|
      io.write lockfile
    end
  end

  def test_add_DEPENDENCIES
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |s|
        s.add_development_dependency 'b'
      end
    end

    @set.gem 'a'
    @set.resolve

    out = []

    lockfile.add_DEPENDENCIES out

    expected = [
      'DEPENDENCIES',
      '  a',
      nil
    ]

    assert_equal expected, out
  end

  def test_add_DEPENDENCIES_from_gem_deps
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |s|
        s.add_development_dependency 'b'
      end
    end

    dependencies = { 'a' => Gem::Requirement.new('~> 2.0') }

    @set.gem 'a'
    @set.resolve
    @lockfile =
      Gem::RequestSet::Lockfile.new @set, @gem_deps_file, dependencies

    out = []

    @lockfile.add_DEPENDENCIES out

    expected = [
      'DEPENDENCIES',
      '  a (~> 2.0)',
      nil
    ]

    assert_equal expected, out
  end

  def test_add_GEM
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |s|
        s.add_dependency 'b'
        s.add_development_dependency 'c'
      end

      fetcher.spec 'b', 2

      fetcher.spec 'bundler', 1
    end

    @set.gem 'a'
    @set.gem 'bundler'
    @set.resolve

    out = []

    lockfile.add_GEM out, lockfile.spec_groups

    expected = [
      'GEM',
      '  remote: http://gems.example.com/',
      '  specs:',
      '    a (2)',
      '      b',
      '    b (2)',
      nil
    ]

    assert_equal expected, out
  end

  def test_add_PLATFORMS
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |s|
        s.add_dependency 'b'
      end

      fetcher.spec 'b', 2 do |s|
        s.platform = Gem::Platform::CURRENT
      end
    end

    @set.gem 'a'
    @set.resolve

    out = []

    lockfile.add_PLATFORMS out

    expected = [
      'PLATFORMS',
      '  ruby',
      '  x86-darwin-8',
      nil
    ]

    assert_equal expected, out
  end

  def test_relative_path_from
    path = lockfile.relative_path_from '/foo', '/foo/bar'

    assert_equal File.expand_path('/foo'), path

    path = lockfile.relative_path_from '/foo', '/foo'

    assert_equal '.', path
  end

  def test_to_s_gem
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_dependency
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'c' => '>= 0', 'b' => '>= 0'
      fetcher.spec 'b', 2
      fetcher.spec 'c', 2
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
      c
    b (2)
    c (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
  c
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_dependency_non_default
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'b' => '>= 1'
      fetcher.spec 'b', 2
    end

    @set.gem 'b'
    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (>= 1)
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_dependency_requirement
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2, 'b' => '>= 0'
      fetcher.spec 'b', 2
    end

    @set.gem 'a', '>= 1'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a (>= 1)
  b
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_path
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, directory

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_path_absolute
    name, version, directory = vendor_gem

    @vendor_set.add_vendor_gem name, File.expand_path(directory)

    @set.gem 'a'

    expected = <<-LOCKFILE
PATH
  remote: #{directory}
  specs:
    #{name} (#{version})

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a!
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_platform
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |spec|
        spec.platform = Gem::Platform.local
      end
    end

    @set.gem 'a'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2-#{Gem::Platform.local})

PLATFORMS
  #{Gem::Platform.local}

DEPENDENCIES
  a
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_gem_source
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
    end

    spec_fetcher 'http://other.example/' do |fetcher|
      fetcher.download 'b', 2
    end

    Gem.sources << 'http://other.example/'

    @set.gem 'a'
    @set.gem 'b'

    expected = <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)

GEM
  remote: http://other.example/
  specs:
    b (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
  b
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_to_s_git
    _, _, repository, = git_gem

    head = nil

    Dir.chdir repository do
      FileUtils.mkdir 'b'

      Dir.chdir 'b' do
        b = Gem::Specification.new 'b', 1 do |s|
          s.add_dependency 'a', '~> 1.0'
          s.add_dependency 'c', '~> 1.0'
        end

        open 'b.gemspec', 'w' do |io|
          io.write b.to_ruby
        end

        system @git, 'add', 'b.gemspec'
        system @git, 'commit', '--quiet', '-m', 'add b/b.gemspec'
      end

      FileUtils.mkdir 'c'

      Dir.chdir 'c' do
        c = Gem::Specification.new 'c', 1

        open 'c.gemspec', 'w' do |io|
          io.write c.to_ruby
        end

        system @git, 'add', 'c.gemspec'
        system @git, 'commit', '--quiet', '-m', 'add c/c.gemspec'
      end

      head = `#{@git} rev-parse HEAD`.strip
    end

    @git_set.add_git_gem 'a', repository, 'HEAD', true
    @git_set.add_git_gem 'b', repository, 'HEAD', true
    @git_set.add_git_gem 'c', repository, 'HEAD', true

    @set.gem 'b'

    expected = <<-LOCKFILE
GIT
  remote: #{repository}
  revision: #{head}
  specs:
    a (1)
    b (1)
      a (~> 1.0)
      c (~> 1.0)
    c (1)

PLATFORMS
  ruby

DEPENDENCIES
  a!
  b!
  c!
    LOCKFILE

    assert_equal expected, lockfile.to_s
  end

  def test_write
    lockfile.write

    gem_deps_lock_file = "#{@gem_deps_file}.lock"

    assert_path_exists gem_deps_lock_file

    refute_empty File.read gem_deps_lock_file
  end

  def test_write_error
    @set.gem 'nonexistent'

    gem_deps_lock_file = "#{@gem_deps_file}.lock"

    open gem_deps_lock_file, 'w' do |io|
      io.write 'hello'
    end

    assert_raises Gem::UnsatisfiableDependencyError do
      lockfile.write
    end

    assert_path_exists gem_deps_lock_file

    assert_equal 'hello', File.read(gem_deps_lock_file)
  end
end
