# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/installer'

class TestGemResolverGitSpecification < Gem::TestCase
  def setup
    super

    @set  = Gem::Resolver::GitSet.new
    @spec = Gem::Specification.new 'a', 1
  end

  def test_equals2
    g_spec_a = Gem::Resolver::GitSpecification.new @set, @spec

    assert_equal g_spec_a, g_spec_a

    spec_b = Gem::Specification.new 'b', 1
    g_spec_b = Gem::Resolver::GitSpecification.new @set, spec_b

    refute_equal g_spec_a, g_spec_b

    g_set = Gem::Resolver::GitSet.new
    g_spec_s = Gem::Resolver::GitSpecification.new g_set, @spec

    refute_equal g_spec_a, g_spec_s

    i_set  = Gem::Resolver::IndexSet.new
    source = Gem::Source.new @gem_repo
    i_spec = Gem::Resolver::IndexSpecification.new(
      i_set, 'a', v(1), source, Gem::Platform::RUBY)

    refute_equal g_spec_a, i_spec
  end

  def test_add_dependency
    git_gem 'a', 1

    git_spec = Gem::Resolver::GitSpecification.new @set, @spec

    b_dep = dep 'b'

    git_spec.add_dependency b_dep

    assert_equal [b_dep], git_spec.dependencies
  end

  def test_install
    git_gem 'a', 1

    git_spec = Gem::Resolver::GitSpecification.new @set, @spec

    called = false

    git_spec.install({}) do |installer|
      called = installer
    end

    assert called
  end

  # functional test for Gem::Ext::Builder

  def test_install_extension
    pend if Gem.java_platform?
    name, _, repository, = git_gem 'a', 1 do |s|
      s.extensions << 'ext/extconf.rb'
    end

    Dir.chdir 'git/a' do
      FileUtils.mkdir_p 'ext/lib'

      File.open 'ext/extconf.rb', 'w' do |io|
        io.puts 'require "mkmf"'
        io.puts 'create_makefile "a"'
      end

      FileUtils.touch 'ext/lib/b.rb'

      system @git, 'add', 'ext/extconf.rb'
      system @git, 'add', 'ext/lib/b.rb'

      system @git, 'commit', '--quiet', '-m', 'Add extension files'
    end

    source = Gem::Source::Git.new name, repository, 'master', true

    spec = source.specs.first

    git_spec = Gem::Resolver::GitSpecification.new @set, spec, source

    git_spec.install({})

    assert_path_exist File.join git_spec.spec.extension_dir, 'b.rb'
  end

  def test_install_installed
    git_gem 'a', 1

    git_spec = Gem::Resolver::GitSpecification.new @set, @spec

    git_spec.install({})

    called = false

    git_spec.install({}) do |installer|
      called = installer
    end

    assert called
  end
end
