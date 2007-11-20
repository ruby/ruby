require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
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

    @b1, @b1_gem = util_gem 'b', '1' do |s| s.add_dependency 'a' end

    @d1, @d1_gem = util_gem 'd', '1'
    @d2, @d2_gem = util_gem 'd', '2'

    @x1_m, @x1_m_gem = util_gem 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @x1_o, @x1_o_gem = util_gem 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    @w1, @w1_gem = util_gem 'w', '1' do |s| s.add_dependency 'x' end

    @y1, @y1_gem = util_gem 'y', '1'
    @y1_1_p, @y1_1_p_gem = util_gem 'y', '1.1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @z1, @z1_gem = util_gem 'z', '1'   do |s| s.add_dependency 'y' end

    si = util_setup_source_info_cache @a1, @b1, @d1, @d2, @x1_m, @x1_o, @w1,
                                      @y1, @y1_1_p, @z1

    @fetcher = FakeFetcher.new
    Gem::RemoteFetcher.instance_variable_set :@fetcher, @fetcher
    @fetcher.uri = URI.parse 'http://gems.example.com'
    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml

    FileUtils.rm_rf File.join(@gemhome, 'gems')
  end

  def test_install
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a'
      inst.install
    end

    assert_equal Gem::SourceIndex.new(@a1.full_name => @a1),
                 Gem::SourceIndex.from_installed_gems

    assert_equal [@a1], inst.installed_gems
  end

  def test_install_dependency
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'b'
      inst.install
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_existing
    Gem::Installer.new(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'b'
      inst.install
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_dependency_old
    e1, e1_gem = util_gem 'e', '1'
    f1, f1_gem = util_gem 'f', '1' do |s| s.add_dependency 'e' end
    f2, f2_gem = util_gem 'f', '2'

    FileUtils.mv e1_gem, @tempdir
    FileUtils.mv f1_gem, @tempdir
    FileUtils.mv f2_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'f'
      inst.install
    end

    assert_equal %w[f-2], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a-1.gem'
      inst.install
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_local_subdir
    inst = nil
    
    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'gems/a-1.gem'
      inst.install
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_env_shebang
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a', nil, :env_shebang => true,
                                          :wrappers => true
      inst.install
    end

    assert_match %r|\A#!/usr/bin/env ruby\n|,
                 File.read(File.join(@gemhome, 'bin', 'a_bin'))
  end

  def test_install_force
    FileUtils.mv @b1_gem, @tempdir
    si = util_setup_source_info_cache @b1
    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'b', nil, :force => true
      inst.install
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_ignore_dependencies
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'b', nil, :ignore_dependencies => true
      inst.install
    end

    assert_equal %w[b-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_install_dir
    FileUtils.mv @a1_gem, @tempdir
    gemhome2 = File.join @tempdir, 'gemhome2'
    Dir.mkdir gemhome2
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a', nil, :install_dir => gemhome2
      inst.install
    end

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }

    assert File.exist?(File.join(gemhome2, 'specifications',
                                 "#{@a1.full_name}.gemspec"))
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
      inst = Gem::DependencyInstaller.new 'b', nil, :domain => :both
      inst.install
    end

    assert_equal %w[a-1 b-1], inst.installed_gems.map { |s| s.full_name }
    a1, b1 = inst.installed_gems

    a1_expected = File.join(@gemhome, 'specifications',
                            "#{a1.full_name}.gemspec")
    b1_expected = File.join(@gemhome, 'specifications',
                            "#{b1.full_name}.gemspec")

    assert_equal a1_expected, a1.loaded_from
    assert_equal b1_expected, b1.loaded_from
  end

  def test_install_domain_local
    FileUtils.mv @b1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      e = assert_raise Gem::InstallError do
        inst = Gem::DependencyInstaller.new 'b', nil, :domain => :local
        inst.install
      end
      assert_equal 'b requires a (>= 0)', e.message
    end

    assert_equal [], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_domain_remote
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    inst = Gem::DependencyInstaller.new 'a', nil, :domain => :remote
    inst.install

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_domain_remote_platform_newer
    a2_o, a2_o_gem = util_gem 'a', '2' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    si = util_setup_source_info_cache @a1, a2_o

    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml

    a1_data = nil
    a2_o_data = nil

    File.open @a1_gem, 'rb' do |fp| a1_data = fp.read end
    File.open a2_o_gem, 'rb' do |fp| a2_o_data = fp.read end

    @fetcher.data["http://gems.example.com/gems/#{@a1.full_name}.gem"] =
      a1_data
    @fetcher.data["http://gems.example.com/gems/#{a2_o.full_name}.gem"] =
      a2_o_data

    inst = Gem::DependencyInstaller.new 'a', nil, :domain => :remote
    inst.install

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_reinstall
    Gem::Installer.new(@a1_gem).install
    FileUtils.mv @a1_gem, @tempdir
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a'
      inst.install
    end

    assert_equal Gem::SourceIndex.new(@a1.full_name => @a1),
                 Gem::SourceIndex.from_installed_gems

    assert_equal %w[a-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_security_policy
    FileUtils.mv @a1_gem, @cache_dir
    FileUtils.mv @b1_gem, @cache_dir
    policy = Gem::Security::HighSecurity
    inst = Gem::DependencyInstaller.new 'b', nil, :security_policy => policy

    e = assert_raise Gem::Exception do
      inst.install
    end

    assert_equal 'Unsigned gem', e.message

    assert_equal %w[], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_wrappers
    FileUtils.mv @a1_gem, @cache_dir
    inst = Gem::DependencyInstaller.new 'a', :wrappers => true

    inst.install

    assert_match %r|This file was generated by RubyGems.|,
                 File.read(File.join(@gemhome, 'bin', 'a_bin'))
  end

  def test_install_version
    FileUtils.mv @d1_gem, @cache_dir
    FileUtils.mv @d2_gem, @cache_dir
    inst = Gem::DependencyInstaller.new 'd', '= 1'

    inst.install

    assert_equal %w[d-1], inst.installed_gems.map { |s| s.full_name }
  end

  def test_install_version_default
    FileUtils.mv @d1_gem, @cache_dir
    FileUtils.mv @d2_gem, @cache_dir
    inst = Gem::DependencyInstaller.new 'd'

    inst.install

    assert_equal %w[d-2], inst.installed_gems.map { |s| s.full_name }
  end

  def test_download
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    inst = Gem::DependencyInstaller.new 'a'

    a1_cache_gem = File.join(@gemhome, 'cache', "#{@a1.full_name}.gem")
    assert_equal a1_cache_gem, inst.download(@a1, 'http://gems.example.com')

    assert File.exist?(a1_cache_gem)
  end

  def test_download_cached
    FileUtils.mv @a1_gem, @cache_dir

    inst = Gem::DependencyInstaller.new 'a'

    assert_equal File.join(@gemhome, 'cache', "#{@a1.full_name}.gem"),
                 inst.download(@a1, 'http://gems.example.com')
  end

  def test_download_local
    FileUtils.mv @a1_gem, @tempdir
    local_path = File.join @tempdir, "#{@a1.full_name}.gem"
    inst = nil

    Dir.chdir @tempdir do
      inst = Gem::DependencyInstaller.new 'a'
    end

    assert_equal File.join(@gemhome, 'cache', "#{@a1.full_name}.gem"),
                 inst.download(@a1, local_path)
  end

  def test_download_install_dir
    a1_data = nil
    File.open @a1_gem, 'rb' do |fp|
      a1_data = fp.read
    end

    @fetcher.data['http://gems.example.com/gems/a-1.gem'] = a1_data

    install_dir = File.join @tempdir, 'more_gems'

    inst = Gem::DependencyInstaller.new 'a', nil, :install_dir => install_dir

    a1_cache_gem = File.join install_dir, 'cache', "#{@a1.full_name}.gem"
    assert_equal a1_cache_gem, inst.download(@a1, 'http://gems.example.com')

    assert File.exist?(a1_cache_gem)
  end

  unless win_platform? then # File.chmod doesn't work
    def test_download_local_read_only
      FileUtils.mv @a1_gem, @tempdir
      local_path = File.join @tempdir, "#{@a1.full_name}.gem"
      inst = nil
      File.chmod 0555, File.join(@gemhome, 'cache')

      Dir.chdir @tempdir do
        inst = Gem::DependencyInstaller.new 'a'
      end

      assert_equal File.join(@tempdir, "#{@a1.full_name}.gem"),
        inst.download(@a1, local_path)
    ensure
      File.chmod 0755, File.join(@gemhome, 'cache')
    end
  end

  def test_download_platform_legacy
    original_platform = 'old-platform'

    e1, e1_gem = util_gem 'e', '1' do |s|
      s.platform = Gem::Platform::CURRENT
      s.instance_variable_set :@original_platform, original_platform
    end

    e1_data = nil
    File.open e1_gem, 'rb' do |fp|
      e1_data = fp.read
    end

    @fetcher.data["http://gems.example.com/gems/e-1-#{original_platform}.gem"] = e1_data

    inst = Gem::DependencyInstaller.new 'a'

    e1_cache_gem = File.join(@gemhome, 'cache', "#{e1.full_name}.gem")
    assert_equal e1_cache_gem, inst.download(e1, 'http://gems.example.com')

    assert File.exist?(e1_cache_gem)
  end

  def test_download_unsupported
    inst = Gem::DependencyInstaller.new 'a'

    e = assert_raise Gem::InstallError do
      inst.download @a1, 'ftp://gems.rubyforge.org'
    end

    assert_equal 'unsupported URI scheme ftp', e.message
  end

  def test_find_gems_gems_with_sources
    inst = Gem::DependencyInstaller.new 'a'
    dep = Gem::Dependency.new 'b', '>= 0'

    assert_equal [[@b1, 'http://gems.example.com']],
                 inst.find_gems_with_sources(dep)
  end

  def test_find_gems_with_sources_local
    FileUtils.mv @a1_gem, @tempdir
    inst = Gem::DependencyInstaller.new 'b'
    dep = Gem::Dependency.new 'a', '>= 0'
    gems = nil

    Dir.chdir @tempdir do
      gems = inst.find_gems_with_sources dep
    end

    assert_equal 2, gems.length
    remote = gems.first
    assert_equal @a1, remote.first, 'remote spec'
    assert_equal 'http://gems.example.com', remote.last, 'remote path'

    local = gems.last
    assert_equal 'a-1', local.first.full_name, 'local spec'
    assert_equal File.join(@tempdir, "#{@a1.full_name}.gem"),
                 local.last, 'local path'
  end

  def test_gather_dependencies
    inst = Gem::DependencyInstaller.new 'b'

    assert_equal %w[a-1 b-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_dropped
    b2, = util_gem 'b', '2'
    c1, = util_gem 'c', '1' do |s| s.add_dependency 'b' end

    si = util_setup_source_info_cache @a1, @b1, b2, c1

    @fetcher = FakeFetcher.new
    Gem::RemoteFetcher.instance_variable_set :@fetcher, @fetcher
    @fetcher.uri = URI.parse 'http://gems.example.com'
    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml

    inst = Gem::DependencyInstaller.new 'c'

    assert_equal %w[b-2 c-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_platform_alternate
    util_set_arch 'cpu-my_platform1'

    inst = Gem::DependencyInstaller.new 'w'

    assert_equal %w[x-1-cpu-my_platform-1 w-1],
                 inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_platform_bump
    inst = Gem::DependencyInstaller.new 'z'

    assert_equal %w[y-1 z-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def test_gather_dependencies_old_required
    e1, = util_gem 'e', '1' do |s| s.add_dependency 'd', '= 1' end

    si = util_setup_source_info_cache @d1, @d2, e1

    @fetcher = FakeFetcher.new
    Gem::RemoteFetcher.instance_variable_set :@fetcher, @fetcher
    @fetcher.uri = URI.parse 'http://gems.example.com'
    @fetcher.data['http://gems.example.com/gems/yaml'] = si.to_yaml

    inst = Gem::DependencyInstaller.new 'e'

    assert_equal %w[d-1 e-1], inst.gems_to_install.map { |s| s.full_name }
  end

  def util_gem(name, version, &block)
    spec = quick_gem(name, version, &block)

    util_build_gem spec

    cache_file = File.join @tempdir, 'gems', "#{spec.original_name}.gem"
    FileUtils.mv File.join(@gemhome, 'cache', "#{spec.original_name}.gem"),
                 cache_file
    FileUtils.rm File.join(@gemhome, 'specifications',
                           "#{spec.full_name}.gemspec")

    spec.loaded_from = nil
    spec.loaded = false

    [spec, cache_file]
  end

end

