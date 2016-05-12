# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/dependency_installer'
require 'rubygems/security'

class TestGemDependencyInstaller < Gem::TestCase

  def setup
    super
    common_installer_setup

    @gems_dir  = File.join @tempdir, 'gems'
    @cache_dir = File.join @gemhome, 'cache'

    FileUtils.mkdir @gems_dir

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    @original_platforms = Gem.platforms
    Gem.platforms = []
  end

  def teardown
    Gem.platforms = @original_platforms
    super
  end

  def util_setup_gems
    @a1, @a1_gem         = util_gem 'a', '1' do |s| s.executables << 'a_bin' end
    @a1_pre, @a1_pre_gem = util_gem 'a', '1.a'
    @b1, @b1_gem         = util_gem 'b', '1' do |s|
      s.add_dependency 'a'
      s.add_development_dependency 'aa'
    end

    @c1, @c1_gem         = util_gem 'c', '1' do |s|
      s.add_development_dependency 'b'
    end

    @d1, @d1_gem         = util_gem 'd', '1' do |s|
      s.add_development_dependency 'c'
    end

    util_clear_gems
    util_reset_gems
  end

  def test_available_set_for_name
    util_setup_gems
    p1a, = util_gem 'a', '10.a'
    util_setup_spec_fetcher p1a, @a1, @a1_pre

    inst = Gem::DependencyInstaller.new

    available = inst.available_set_for 'a', Gem::Requirement.default

    assert_equal %w[a-1], available.set.map { |s| s.spec.full_name }
  end

  def test_available_set_for_name_prerelease
    util_setup_gems
    p1a, = util_gem 'a', '10.a'
    util_setup_spec_fetcher p1a, @a1, @a1_pre

    inst = Gem::DependencyInstaller.new :prerelease => true

    available = inst.available_set_for 'a', Gem::Requirement.default

    assert_equal %w[a-10.a],
                 available.sorted.map { |s| s.spec.full_name }
  end

  def test_available_set_for_dep
    util_setup_gems
    p1a, = util_gem 'a', '10.a'
    util_setup_spec_fetcher p1a, @a1, @a1_pre

    inst = Gem::DependencyInstaller.new

    dep = Gem::Dependency.new 'a', Gem::Requirement.default

    available = inst.available_set_for dep, Gem::Requirement.default

    assert_equal %w[a-1], available.set.map { |s| s.spec.full_name }
  end

  def test_available_set_for_dep_prerelease
    util_setup_gems
    p1a, = util_gem 'a', '10.a'
    util_setup_spec_fetcher p1a, @a1, @a1_pre

    inst = Gem::DependencyInstaller.new :prerelease => true

    dep = Gem::Dependency.new 'a', Gem::Requirement.default
    dep.prerelease = true

    available = inst.available_set_for dep, Gem::Requirement.default

    assert_equal %w[a-10.a],
                 available.sorted.map { |s| s.spec.full_name }
  end

  def test_install
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a'
    end

    assert_equal %w[a-1], Gem::Specification.map(&:full_name)
    assert_equal [@a1], inst.installed_gems
  end

  def test_install_prerelease
    util_setup_gems

    p1a, gem = util_gem 'a', '10.a'

    util_setup_spec_fetcher(p1a, @a1, @a1_pre)
    util_clear_gems

    p1a_data = Gem.read_binary(gem)

    @fetcher.data['http://gems.example.com/gems/a-10.a.gem'] = p1a_data

    dep = Gem::Dependency.new "a"
    inst = Gem::DependencyInstaller.new :prerelease => true
    inst.install dep

    assert_equal %w[a-10.a], Gem::Specification.map(&:full_name)
    assert_equal [p1a], inst.installed_gems
  end

  def test_install_prerelease_bug_990
    spec_fetcher do |fetcher|
      fetcher.gem 'a', '1.b' do |s|
        s.add_dependency 'b', '~> 1.a'
      end

      fetcher.gem 'b', '1.b' do |s|
        s.add_dependency 'c', '>= 1'
      end

      fetcher.gem 'c', '1.1.b'
    end

    dep = Gem::Dependency.new 'a'

    inst = Gem::DependencyInstaller.new :prerelease => true
    inst.install dep

    assert_equal %w[a-1.b b-1.b c-1.1.b], Gem::Specification.map(&:full_name)
  end

  def test_install_when_only_prerelease
    p1a, gem = util_gem 'p', '1.a'

    util_setup_spec_fetcher(p1a)
    util_clear_gems

    p1a_data = Gem.read_binary(gem)

    @fetcher.data['http://gems.example.com/gems/p-1.a.gem'] = p1a_data

    dep = Gem::Dependency.new "p"
    inst = Gem::DependencyInstaller.new
    assert_raises Gem::UnsatisfiableDependencyError do
      inst.install dep
    end

    assert_equal %w[], Gem::Specification.map(&:full_name)
    assert_equal [], inst.installed_gems
  end

  def test_install_prerelease_skipped_when_normal_ver
    util_setup_gems

    util_setup_spec_fetcher(@a1, @a1_pre)
    util_clear_gems

    p1a_data = Gem.read_binary(@a1_gem)

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = p1a_data

    dep = Gem::Dependency.new "a"
    inst = Gem::DependencyInstaller.new :prerelease => true
    inst.install dep

    assert_equal %w[a-1], Gem::Specification.map(&:full_name)
    assert_equal [@a1], inst.installed_gems
  end

  def test_install_all_dependencies
    util_setup_gems

    _, e1_gem = util_gem 'e', '1' do |s|
      s.add_dependency 'b'
    end

    util_clear_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv  e1_gem, @tempdir

    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :ignore_dependencies => true
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name },
                 'sanity check'

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'e'
    end

    assert_equal %w[a-1 e-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_cache_dir
    util_setup_gems

    dir = "dir"
    Dir.mkdir dir
    FileUtils.mv @a1_gem, dir
    FileUtils.mv @b1_gem, dir
    inst = nil

    Dir.chdir dir do
      inst = Gem::DependencyInstaller.new :cache_dir => @tempdir
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }

    assert File.exist? File.join(@gemhome, "cache", @a1.file_name)
    assert File.exist? File.join(@gemhome, "cache", @b1.file_name)
  end

  def test_install_dependencies_satisfied
    util_setup_gems

    a2, a2_gem = util_gem 'a', '2'

    FileUtils.rm_rf File.join(@gemhome, 'gems')

    Gem::Specification.reset

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv  a2_gem, @tempdir # not in index
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a', req("= 2")
    end

    assert_equal %w[a-2], inst.installed_gems.map { |s| s.full_name },
                 'sanity check'

    FileUtils.rm File.join(@tempdir, a2.file_name)

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[a-2 b-1], Gem::Specification.map(&:full_name)
    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  # This asserts that if a gem's dependency is satisfied by an
  # already installed gem, RubyGems doesn't installed a newer
  # version
  def test_install_doesnt_upgrade_installed_dependencies
    util_setup_gems

    a2, a2_gem = util_gem 'a', '2'
    a3, a3_gem = util_gem 'a', '3'

    util_setup_spec_fetcher @a1, a3, @b1

    FileUtils.rm_rf File.join(@gemhome, 'gems')

    Gem::Specification.reset

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv  a2_gem, @tempdir # not in index
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv  a3_gem, @tempdir

    Dir.chdir @tempdir do
      Gem::DependencyInstaller.new.install 'a', req("= 2")
    end

    FileUtils.rm File.join(@tempdir, a2.file_name)

    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[a-2 b-1], Gem::Specification.map(&:full_name)
    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency
    util_setup_gems

    done_installing_ran = false
    inst = nil

    Gem.done_installing do |installer, specs|
      done_installing_ran = true
      refute_nil installer
      assert_equal [@a1, @b1], specs
    end

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new(:build_docs_in_background => false)
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }

    assert done_installing_ran, 'post installs hook was not run'
  end

  def test_install_dependency_development
    util_setup_gems

    @aa1, @aa1_gem = util_gem 'aa', '1'

    util_reset_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @aa1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new(:development => true)
      inst.install 'b'
    end

    assert_equal %w[a-1 aa-1 b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_development_deep
    util_setup_gems

    @aa1, @aa1_gem = util_gem 'aa', '1'

    util_reset_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @aa1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv @c1_gem, @tempdir
    FileUtils.mv @d1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new(:development => true)
      inst.install 'd'
    end

    assert_equal %w[a-1 aa-1 b-1 c-1 d-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_development_shallow
    util_setup_gems

    @aa1, @aa1_gem = util_gem 'aa', '1'

    util_reset_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @aa1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv @c1_gem, @tempdir
    FileUtils.mv @d1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new(:development => true, :dev_shallow => true)
      inst.install 'd'
    end

    assert_equal %w[c-1 d-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_existing
    util_setup_gems

    Gem::Installer.at(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_existing_extension
    extconf_rb = File.join @gemhome, 'gems', 'e-1', 'extconf.rb'
    FileUtils.mkdir_p File.dirname extconf_rb

    open extconf_rb, 'w' do |io|
      io.write <<-EXTCONF_RB
        require 'mkmf'
        create_makefile 'e'
      EXTCONF_RB
    end

    e1 = new_spec 'e', '1', nil, 'extconf.rb' do |s|
      s.extensions << 'extconf.rb'
    end
    e1_gem = File.join @tempdir, 'gems', "#{e1.full_name}.gem"

    _, f1_gem = util_gem 'f', '1', 'e' => nil

    Gem::Installer.at(e1_gem).install
    FileUtils.rm_r e1.extension_dir

    FileUtils.mv e1_gem, @tempdir
    FileUtils.mv f1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'f'
    end

    assert_equal %w[f-1], inst.installed_gems.map { |s| s.full_name }

    assert_path_exists e1.extension_dir
  end

  def test_install_dependency_old
    _, e1_gem = util_gem 'e', '1'
    _, f1_gem = util_gem 'f', '1', 'e' => nil
    _, f2_gem = util_gem 'f', '2'

    FileUtils.mv e1_gem, @tempdir
    FileUtils.mv f1_gem, @tempdir
    FileUtils.mv f2_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'f'
    end

    assert_equal %w[f-2], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'a-1.gem'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_prerelease
    util_setup_gems

    FileUtils.mv @a1_pre_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'a-1.a.gem'
    end

    assert_equal %w[a-1.a], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_dependency
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'b-1.gem'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_dependency_installed
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = nil

    Dir.chdir @tempdir do
      Gem::Installer.at('a-1.gem').install

      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'b-1.gem'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_subdir
    util_setup_gems

    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'gems/a-1.gem'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_minimal_deps
    util_setup_gems

    _, e1_gem = util_gem 'e', '1' do |s|
      s.add_dependency 'b'
    end

    _, b2_gem = util_gem 'b', '2' do |s|
      s.add_dependency 'a'
    end

    util_clear_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv  b2_gem, @tempdir
    FileUtils.mv  e1_gem, @tempdir

    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :ignore_dependencies => true
      inst.install 'b', req('= 1')
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name },
                 'sanity check'

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :minimal_deps => true
      inst.install 'e'
    end

    assert_equal %w[a-1 e-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_no_document
    util_setup_gems

    done_installing_called = false

    Gem.done_installing do |dep_installer, specs|
      done_installing_called = true
      assert_empty dep_installer.document
    end

    inst = Gem::DependencyInstaller.new :domain => :local, :document => []

    inst.install @a1_gem

    assert done_installing_called
  end

  def test_install_env_shebang
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :env_shebang => true, :wrappers => true, :format_executable => false
      inst.install 'a'
    end

    env = "/\\S+/env" unless Gem.win_platform?

    assert_match %r|\A#!#{env} #{RbConfig::CONFIG['ruby_install_name']}\n|,
                 File.read(File.join(@gemhome, 'bin', 'a_bin'))
  end

  def test_install_force
    util_setup_gems

    FileUtils.mv @b1_gem, @tempdir
    si = util_setup_spec_fetcher @b1
    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :force => true
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_build_args
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    inst = nil
    build_args = %w[--a --b="c"]

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new(
        :build_args => build_args)
      inst.install 'a'
    end

    assert_equal build_args.join("\n"), File.read(inst.installed_gems.first.build_info_file).strip
  end

  def test_install_ignore_dependencies
    util_setup_gems

    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :ignore_dependencies => true
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_install_dir
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = Gem::Installer.at @a1.file_name
    inst.install

    gemhome2 = File.join @tempdir, 'gemhome2'
    Dir.mkdir gemhome2
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :install_dir => gemhome2
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }

    assert File.exist?(File.join(gemhome2, 'specifications', @a1.spec_name))
    assert File.exist?(File.join(gemhome2, 'cache', @a1.file_name))
  end

  def test_install_domain_both
    util_setup_gems

    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :both
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
    a1, b1 = inst.installed_gems

    assert_equal a1.spec_file, a1.loaded_from
    assert_equal b1.spec_file, b1.loaded_from
  end

  def test_install_domain_both_no_network
    util_setup_gems

    @fetcher.data["http://gems.example.com/gems/Marshal.#{@marshal_version}"] =
      proc do
        raise Gem::RemoteFetcher::FetchError
      end

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :both
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_domain_local
    util_setup_gems

    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      e = assert_raises Gem::UnsatisfiableDependencyError do
        inst = Gem::DependencyInstaller.new :domain => :local
        inst.install 'b'
      end

      expected = "Unable to resolve dependency: 'b (>= 0)' requires 'a (>= 0)'"
      assert_equal expected, e.message
    end

    assert_equal [], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_domain_remote
    util_setup_gems

    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    inst = Gem::DependencyInstaller.new :domain => :remote
    inst.install 'a'

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dual_repository
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    gemhome2 = "#{@gemhome}2"

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :install_dir => gemhome2
      inst.install 'a'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name },
                 'sanity check'

    ENV['GEM_HOME'] = @gemhome
    ENV['GEM_PATH'] = [@gemhome, gemhome2].join File::PATH_SEPARATOR
    Gem.clear_paths

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_reinstall
    util_setup_gems

    Gem::Installer.at(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a'
    end

    assert_equal %w[a-1], Gem::Specification.map(&:full_name)
    assert_equal %w[a-1], inst.installed_gems.map(&:full_name)
  end

  def test_install_remote
    util_setup_gems

    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    inst = Gem::DependencyInstaller.new

    Dir.chdir @tempdir do
      inst.install 'a'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_remote_dep
    util_setup_gems

    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    inst = Gem::DependencyInstaller.new

    Dir.chdir @tempdir do
      dep = Gem::Dependency.new @a1.name, @a1.version
      inst.install dep
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_remote_platform_newer
    util_setup_gems

    a2_o, a2_o_gem = util_gem 'a', '2' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    si = util_setup_spec_fetcher @a1, a2_o

    util_clear_gems

    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml

    a1_data = nil
    a2_o_data = nil

    File.open @a1_gem, 'rb' do |fp| a1_data = fp.read end
    File.open a2_o_gem, 'rb' do |fp| a2_o_data = fp.read end

    @fetcher.data["http://gems.example.com/gems/#{@a1.file_name}"] =
      a1_data
    @fetcher.data["http://gems.example.com/gems/#{a2_o.file_name}"] =
      a2_o_data

    inst = Gem::DependencyInstaller.new :domain => :remote
    inst.install 'a'

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_platform_is_ignored_when_a_file_is_specified
    _, a_gem = util_gem 'a', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    inst = Gem::DependencyInstaller.new :domain => :local
    inst.install a_gem

    assert_equal %w[a-1-cpu-other_platform-1], inst.installed_gems.map { |s| s.full_name }
  end

  if defined? OpenSSL then
    def test_install_security_policy
      util_setup_gems

      data = File.open(@a1_gem, 'rb') { |f| f.read }
      @fetcher.data['http://gems.example.com/gems/a-1.gem'] = data

      data = File.open(@b1_gem, 'rb') { |f| f.read }
      @fetcher.data['http://gems.example.com/gems/b-1.gem'] = data

      policy = Gem::Security::HighSecurity
      inst = Gem::DependencyInstaller.new :security_policy => policy

      e = assert_raises Gem::Security::Exception do
        inst.install 'b'
      end

      assert_equal 'unsigned gems are not allowed by the High Security policy',
                   e.message

      assert_equal %w[], inst.installed_gems.map { |s| s.full_name }
    end
  end

  # Wrappers don't work on mswin
  unless win_platform? then
    def test_install_no_wrappers
      util_setup_gems

      @fetcher.data['http://gems.example.com/gems/a-1.gem'] = read_binary(@a1_gem)

      inst = Gem::DependencyInstaller.new :wrappers => false, :format_executable => false
      inst.install 'a'

      refute_match(%r|This file was generated by RubyGems.|,
                   File.read(File.join(@gemhome, 'bin', 'a_bin')))
    end
  end

  def test_install_version
    util_setup_d

    data = File.open(@d2_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-2.gem'] = data

    data = File.open(@d1_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-1.gem'] = data

    inst = Gem::DependencyInstaller.new

    inst.install 'd', '= 1'

    assert_equal %w[d-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_version_default
    util_setup_d

    data = File.open(@d2_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-2.gem'] = data

    data = File.open(@d1_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-1.gem'] = data

    inst = Gem::DependencyInstaller.new
    inst.install 'd'

    assert_equal %w[d-2], inst.installed_gems.map { |s| s.full_name }
  end

  def test_find_gems_gems_with_sources
    util_setup_gems

    inst = Gem::DependencyInstaller.new
    dep = Gem::Dependency.new 'b', '>= 0'

    Gem::Specification.reset

    set = inst.find_gems_with_sources(dep)

    assert_kind_of Gem::AvailableSet, set

    s = set.set.first

    assert_equal @b1, s.spec
    assert_equal Gem::Source.new(@gem_repo), s.source
  end

  def test_find_spec_by_name_and_version_wildcard
    util_gem 'a', 1
    FileUtils.mv 'gems/a-1.gem', @tempdir

    FileUtils.touch 'rdoc.gem'

    inst = Gem::DependencyInstaller.new

    available = inst.find_spec_by_name_and_version('*.gem')

    assert_equal %w[a-1], available.each_spec.map { |spec| spec.full_name }
  end

  def test_find_spec_by_name_and_version_wildcard_bad_gem
    FileUtils.touch 'rdoc.gem'

    inst = Gem::DependencyInstaller.new

    assert_raises Gem::Package::FormatError do
      inst.find_spec_by_name_and_version '*.gem'
    end
  end

  def test_find_spec_by_name_and_version_bad_gem
    FileUtils.touch 'rdoc.gem'

    inst = Gem::DependencyInstaller.new

    e = assert_raises Gem::Package::FormatError do
      inst.find_spec_by_name_and_version 'rdoc.gem'
    end

    full_path = File.join @tempdir, 'rdoc.gem'
    assert_equal "package metadata is missing in #{full_path}", e.message
  end

  def test_find_spec_by_name_and_version_directory
    Dir.mkdir 'rdoc'

    inst = Gem::DependencyInstaller.new

    e = assert_raises Gem::SpecificGemNotFoundException do
      inst.find_spec_by_name_and_version 'rdoc'
    end

    assert_equal "Could not find a valid gem 'rdoc' (>= 0) " +
                 "locally or in a repository",
                 e.message
  end

  def test_find_spec_by_name_and_version_file
    FileUtils.touch 'rdoc'

    inst = Gem::DependencyInstaller.new

    e = assert_raises Gem::SpecificGemNotFoundException do
      inst.find_spec_by_name_and_version 'rdoc'
    end

    assert_equal "Could not find a valid gem 'rdoc' (>= 0) " +
                 "locally or in a repository",
                 e.message
  end

  def test_find_gems_with_sources_local
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    inst = Gem::DependencyInstaller.new
    dep = Gem::Dependency.new 'a', '>= 0'
    set = nil

    Dir.chdir @tempdir do
      set = inst.find_gems_with_sources dep
    end

    gems = set.sorted

    assert_equal 2, gems.length

    remote, local = gems

    assert_equal 'a-1', local.spec.full_name, 'local spec'
    assert_equal File.join(@tempdir, @a1.file_name),
                 local.source.download(local.spec), 'local path'

    assert_equal 'a-1', remote.spec.full_name, 'remote spec'
    assert_equal Gem::Source.new(@gem_repo), remote.source, 'remote path'

  end

  def test_find_gems_with_sources_prerelease
    util_setup_gems

    installer = Gem::DependencyInstaller.new

    dependency = Gem::Dependency.new('a', Gem::Requirement.default)

    releases =
      installer.find_gems_with_sources(dependency).all_specs

    assert releases.any? { |s| s.name == 'a' and s.version.to_s == '1' }
    refute releases.any? { |s| s.name == 'a' and s.version.to_s == '1.a' }

    dependency.prerelease = true

    prereleases =
      installer.find_gems_with_sources(dependency).all_specs

    assert_equal [@a1_pre, @a1], prereleases
  end

  def test_find_gems_with_sources_with_best_only_and_platform
    util_setup_gems
    a1_x86_mingw32, = util_gem 'a', '1' do |s|
      s.platform = 'x86-mingw32'
    end
    util_setup_spec_fetcher @a1, a1_x86_mingw32
    Gem.platforms << Gem::Platform.new('x86-mingw32')

    installer = Gem::DependencyInstaller.new

    dependency = Gem::Dependency.new('a', Gem::Requirement.default)

    releases =
      installer.find_gems_with_sources(dependency, true).all_specs

    assert_equal [a1_x86_mingw32], releases
  end

  def test_find_gems_with_sources_with_bad_source
    Gem.sources.replace ["http://not-there.nothing"]

    installer = Gem::DependencyInstaller.new

    dep = Gem::Dependency.new('a')

    out = installer.find_gems_with_sources(dep)

    assert out.empty?
    assert_kind_of Gem::SourceFetchProblem, installer.errors.first
  end

  def test_resolve_dependencies
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = Gem::DependencyInstaller.new
    request_set = inst.resolve_dependencies 'b', req('>= 0')

    requests = request_set.sorted_requests.map { |req| req.full_name }

    assert_equal %w[a-1 b-1], requests
  end

  def test_resolve_dependencies_ignore_dependencies
    util_setup_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = Gem::DependencyInstaller.new :ignore_dependencies => true
    request_set = inst.resolve_dependencies 'b', req('>= 0')

    requests = request_set.sorted_requests.map { |req| req.full_name }

    assert request_set.ignore_dependencies

    assert_equal %w[b-1], requests
  end

  def test_resolve_dependencies_local
    util_setup_gems

    @a2, @a2_gem = util_gem 'a', '2'
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @a2_gem, @tempdir

    inst = Gem::DependencyInstaller.new
    request_set = inst.resolve_dependencies 'a-1.gem', req('>= 0')

    requests = request_set.sorted_requests.map { |req| req.full_name }

    assert_equal %w[a-1], requests
  end

  def util_write_a1_bin
    write_file File.join('gems', 'a-1', 'bin', 'a_bin') do |fp|
      fp.puts "#!/usr/bin/ruby"
    end
  end

  def util_setup_c1_pre
    @c1_pre, @c1_pre_gem = util_spec 'c', '1.a' do |s|
      s.add_dependency 'a', '1.a'
      s.add_dependency 'b', '1'
    end

    util_reset_gems
  end

  def util_setup_d
    @d1, @d1_gem = util_gem 'd', '1'
    @d2, @d2_gem = util_gem 'd', '2'

    util_reset_gems
  end

  def util_setup_wxyz
    @x1_m, @x1_m_gem = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @x1_o, @x1_o_gem = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    @w1, @w1_gem = util_spec 'w', '1', 'x' => nil

    @y1, @y1_gem = util_spec 'y', '1'
    @y1_1_p, @y1_1_p_gem = util_spec 'y', '1.1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @z1, @z1_gem = util_spec 'z', '1', 'y' => nil

    util_reset_gems
  end

  def util_reset_gems
    @a1     ||= nil
    @b1     ||= nil
    @a1_pre ||= nil
    @c1_pre ||= nil
    @d1     ||= nil
    @d2     ||= nil
    @w1     ||= nil
    @x1_m   ||= nil
    @x1_o   ||= nil
    @y1     ||= nil
    @y1_1_p ||= nil
    @z1     ||= nil

    util_setup_spec_fetcher(*[@a1, @a1_pre, @b1, @c1_pre,
                              @d1, @d2, @x1_m, @x1_o, @w1, @y1,
                              @y1_1_p, @z1].compact)

    util_clear_gems
  end
end
