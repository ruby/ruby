######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/dependency_installer'

class TestGemDependencyInstaller < RubyGemTestCase

  def setup
    super

    @gems_dir = File.join @tempdir, 'gems'
    @cache_dir = File.join @gemhome, 'cache'
    FileUtils.mkdir @gems_dir

    write_file File.join('gems', 'a-1', 'bin', 'a_bin') do |fp|
      fp.puts "#!/usr/bin/ruby"
    end

    @a1, @a1_gem = util_gem 'a', '1' do |s| s.executables << 'a_bin' end
    @aa1, @aa1_gem = util_gem 'aa', '1'
    @a1_pre, @a1_pre_gem = util_gem 'a', '1.a'

    @b1, @b1_gem = util_gem 'b', '1' do |s|
      s.add_dependency 'a'
      s.add_development_dependency 'aa'
    end

    @b1_pre, @b1_pre_gem = util_gem 'b', '1.a' do |s|
      s.add_dependency 'a'
      s.add_development_dependency 'aa'
    end

    @c1_pre, @c1_pre_gem = util_gem 'c', '1.a' do |s|
      s.add_dependency 'a', '1.a'
      s.add_dependency 'b', '1'
    end

    @d1, @d1_gem = util_gem 'd', '1'
    @d2, @d2_gem = util_gem 'd', '2'

    @x1_m, @x1_m_gem = util_gem 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @x1_o, @x1_o_gem = util_gem 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    @w1, @w1_gem = util_gem 'w', '1', 'x' => nil

    @y1, @y1_gem = util_gem 'y', '1'
    @y1_1_p, @y1_1_p_gem = util_gem 'y', '1.1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @z1, @z1_gem = util_gem 'z', '1', 'y' => nil

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher(@a1, @a1_pre, @b1, @b1_pre, @c1_pre, @d1, @d2,
                            @x1_m, @x1_o, @w1, @y1, @y1_1_p, @z1)

    util_clear_gems
  end

  def test_install
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a'
    end

    assert_equal Gem::SourceIndex.new(@a1.full_name => @a1),
                 Gem::SourceIndex.from_installed_gems

    assert_equal [@a1], inst.installed_gems
  end

  def test_install_all_dependencies
    _, e1_gem = util_gem 'e', '1' do |s|
      s.add_dependency 'b'
    end

    util_clear_gems

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    FileUtils.mv e1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :ignore_dependencies => true
      inst.install 'b'
    end

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'e'
    end

    assert_equal %w[e-1 a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_cache_dir
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :cache_dir => @tempdir
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }

    assert File.exist?(File.join(@tempdir, 'cache', @a1.file_name))
    assert File.exist?(File.join(@tempdir, 'cache', @b1.file_name))
  end

  def test_install_dependencies_satisfied
    a2, a2_gem = util_gem 'a', '2'

    FileUtils.rm_rf File.join(@gemhome, 'gems')
    Gem.source_index.refresh!

    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv a2_gem, @tempdir # not in index
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a-2'
    end

    FileUtils.rm File.join(@tempdir, a2.file_name)

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    installed = Gem::SourceIndex.from_installed_gems.map { |n,s| s.full_name }

    assert_equal %w[a-2 b-1], installed.sort

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_development
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

  def test_install_dependency_existing
    Gem::Installer.new(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
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
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'a-1.gem'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_dependency
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
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir

    inst = nil

    Dir.chdir @tempdir do
      Gem::Installer.new('a-1.gem').install

      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'b-1.gem'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_subdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :domain => :local
      inst.install 'gems/a-1.gem'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_env_shebang
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :env_shebang => true, :wrappers => true
      inst.install 'a'
    end

    env = "/\\S+/env" unless Gem.win_platform?

    assert_match %r|\A#!#{env} #{Gem::ConfigMap[:ruby_install_name]}\n|,
                 File.read(File.join(@gemhome, 'bin', 'a_bin'))
  end

  def test_install_force
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

  def test_install_ignore_dependencies
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :ignore_dependencies => true
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_install_dir
    FileUtils.mv @a1_gem, @tempdir
    gemhome2 = File.join @tempdir, 'gemhome2'
    Dir.mkdir gemhome2
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :install_dir => gemhome2
      inst.install 'a'
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }

    assert File.exist?(File.join(gemhome2, 'specifications', @a1.spec_name))
    assert File.exist?(File.join(gemhome2, 'cache', @a1.file_name))
  end

  def test_install_domain_both
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

    a1_expected = File.join(@gemhome, 'specifications', a1.spec_name)
    b1_expected = File.join(@gemhome, 'specifications', b1.spec_name)

    assert_equal a1_expected, a1.loaded_from
    assert_equal b1_expected, b1.loaded_from
  end

  def test_install_domain_both_no_network
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
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Gem.source_index.remove_spec @a1.full_name
    Gem.source_index.remove_spec @a1_pre.full_name

    Dir.chdir @tempdir do
      e = assert_raises Gem::InstallError do
        inst = Gem::DependencyInstaller.new :domain => :local
        inst.install 'b'
      end

      assert_equal 'b requires a (>= 0, runtime)', e.message
    end

    assert_equal [], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_domain_remote
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
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    gemhome2 = "#{@gemhome}2"

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new :install_dir => gemhome2
      inst.install 'a'
    end

    ENV['GEM_HOME'] = @gemhome
    ENV['GEM_PATH'] = [@gemhome, gemhome2].join File::PATH_SEPARATOR
    Gem.clear_paths

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'b'
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_remote
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

  def test_install_domain_remote_platform_newer
    a2_o, a2_o_gem = util_gem 'a', '2' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    util_clear_gems

    si = util_setup_spec_fetcher @a1, a2_o

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

  def test_install_reinstall
    Gem::Installer.new(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new
      inst.install 'a'
    end

    assert_equal Gem::SourceIndex.new(@a1.full_name => @a1),
                 Gem::SourceIndex.from_installed_gems

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  if defined? OpenSSL then
    def test_install_security_policy
      data = File.open(@a1_gem, 'rb') { |f| f.read }
      @fetcher.data['http://gems.example.com/gems/a-1.gem'] = data

      data = File.open(@b1_gem, 'rb') { |f| f.read }
      @fetcher.data['http://gems.example.com/gems/b-1.gem'] = data

      policy = Gem::Security::HighSecurity
      inst = Gem::DependencyInstaller.new :security_policy => policy

      e = assert_raises Gem::Exception do
        inst.install 'b'
      end

      assert_equal 'Unsigned gem', e.message

      assert_equal %w[], inst.installed_gems.map { |s| s.full_name }
    end
  end

  # Wrappers don't work on mswin
  unless win_platform? then
    def test_install_no_wrappers
      @fetcher.data['http://gems.example.com/gems/a-1.gem'] = read_binary(@a1_gem)

      inst = Gem::DependencyInstaller.new :wrappers => false
      inst.install 'a'

      refute_match(%r|This file was generated by RubyGems.|,
                   File.read(File.join(@gemhome, 'bin', 'a_bin')))
    end
  end

  def test_install_version
    data = File.open(@d2_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-2.gem'] = data

    data = File.open(@d1_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-1.gem'] = data

    inst = Gem::DependencyInstaller.new

    inst.install 'd', '= 1'

    assert_equal %w[d-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_version_default
    data = File.open(@d2_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-2.gem'] = data

    data = File.open(@d1_gem, 'rb') { |f| f.read }
    @fetcher.data['http://gems.example.com/gems/d-1.gem'] = data

    inst = Gem::DependencyInstaller.new
    inst.install 'd'

    assert_equal %w[d-2], inst.installed_gems.map { |s| s.full_name }
  end

  def test_find_gems_gems_with_sources
    inst = Gem::DependencyInstaller.new
    dep = Gem::Dependency.new 'b', '>= 0'

    assert_equal [[@b1, @gem_repo]],
                 inst.find_gems_with_sources(dep)
  end

  def test_find_gems_with_sources_local
    FileUtils.mv @a1_gem, @tempdir
    inst = Gem::DependencyInstaller.new
    dep = Gem::Dependency.new 'a', '>= 0'
    gems = nil

    Dir.chdir @tempdir do
      gems = inst.find_gems_with_sources dep
    end

    assert_equal 2, gems.length
    remote = gems.first
    assert_equal 'a-1', remote.first.full_name, 'remote spec'
    assert_equal @gem_repo, remote.last, 'remote path'

    local = gems.last
    assert_equal 'a-1', local.first.full_name, 'local spec'
    assert_equal File.join(@tempdir, @a1.file_name),
                 local.last, 'local path'
  end

  def test_find_gems_with_sources_prerelease
    installer = Gem::DependencyInstaller.new

    dependency = Gem::Dependency.new('a', Gem::Requirement.default)

    releases =
      installer.find_gems_with_sources(dependency).map { |gems, *| gems }

    assert releases.any? { |s| s.name == 'a' and s.version.to_s == '1' }
    refute releases.any? { |s| s.name == 'a' and s.version.to_s == '1.a' }

    dependency.prerelease = true

    prereleases =
      installer.find_gems_with_sources(dependency).map { |gems, *| gems }

    assert_equal [@a1_pre], prereleases
  end

  def assert_resolve expected, *specs
    util_clear_gems

    util_setup_spec_fetcher(*specs)

    inst = Gem::DependencyInstaller.new
    inst.find_spec_by_name_and_version 'a'
    inst.gather_dependencies

    actual = inst.gems_to_install.map { |s| s.full_name }
    assert_equal expected, actual
  end

  def test_gather_dependencies
    inst = Gem::DependencyInstaller.new
    inst.find_spec_by_name_and_version 'b'
    inst.gather_dependencies

    assert_equal %w[a-1 b-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_platform_alternate
    util_set_arch 'cpu-my_platform1'

    inst = Gem::DependencyInstaller.new
    inst.find_spec_by_name_and_version 'w'
    inst.gather_dependencies

    assert_equal %w[x-1-cpu-my_platform-1 w-1],
                 inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_platform_bump
    inst = Gem::DependencyInstaller.new
    inst.find_spec_by_name_and_version 'z'
    inst.gather_dependencies

    assert_equal %w[y-1 z-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_prerelease
    inst = Gem::DependencyInstaller.new :prerelease => true
    inst.find_spec_by_name_and_version 'c', '1.a'
    inst.gather_dependencies

    assert_equal %w[a-1.a b-1 c-1.a],
                 inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_old_required
    e1, = util_gem 'e', '1', 'd' => '= 1'

    util_clear_gems

    util_setup_spec_fetcher @d1, @d2, e1

    inst = Gem::DependencyInstaller.new
    inst.find_spec_by_name_and_version 'e'
    inst.gather_dependencies

    assert_equal %w[d-1 e-1], inst.gems_to_install.map { |s| s.full_name }
  end

end

