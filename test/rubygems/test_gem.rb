require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems'
require 'rubygems/gem_openssl'
require 'rubygems/installer'
require 'pathname'
require 'tmpdir'

class TestGem < RubyGemTestCase

  def setup
    super

    @additional = %w[a b].map { |d| File.join @tempdir, d }
    @default_dir_re = %r|/[Rr]uby/[Gg]ems/[0-9.]+|
  end

  def test_self_all_load_paths
    util_make_gems

    expected = [
      File.join(@gemhome, *%W[gems #{@a1.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@a2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@a_evil9.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@b2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@c1_2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@pl1.full_name} lib]),
    ]

    assert_equal expected, Gem.all_load_paths.sort
  end

  def test_self_available?
    util_make_gems
    assert(Gem.available?("a"))
    assert(Gem.available?("a", "1"))
    assert(Gem.available?("a", ">1"))
    assert(!Gem.available?("monkeys"))
  end

  def test_self_bindir
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir(Gem.dir)
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir(Pathname.new(Gem.dir))
  end

  def test_self_bindir_default_dir
    default = Gem.default_dir
    bindir = if defined?(RUBY_FRAMEWORK_VERSION) then
               '/usr/bin'
             else
               Config::CONFIG['bindir']
             end

    assert_equal bindir, Gem.bindir(default)
    assert_equal bindir, Gem.bindir(Pathname.new(default))
  end

  def test_self_clear_paths
    Gem.dir
    Gem.path
    searcher = Gem.searcher
    source_index = Gem.source_index

    Gem.clear_paths

    assert_equal nil, Gem.instance_variable_get(:@gem_home)
    assert_equal nil, Gem.instance_variable_get(:@gem_path)
    refute_equal searcher, Gem.searcher
    refute_equal source_index.object_id, Gem.source_index.object_id
  end

  def test_self_configuration
    expected = Gem::ConfigFile.new []
    Gem.configuration = nil

    assert_equal expected, Gem.configuration
  end

  def test_self_datadir
    foo = nil

    Dir.chdir @tempdir do
      FileUtils.mkdir_p 'data'
      File.open File.join('data', 'foo.txt'), 'w' do |fp|
        fp.puts 'blah'
      end

      foo = quick_gem 'foo' do |s| s.files = %w[data/foo.txt] end
      install_gem foo
    end

    Gem.source_index = nil

    gem 'foo'

    expected = File.join @gemhome, 'gems', foo.full_name, 'data', 'foo'

    assert_equal expected, Gem.datadir('foo')
  end

  def test_self_datadir_nonexistent_package
    assert_nil Gem.datadir('xyzzy')
  end

  def test_self_default_dir
    assert_match @default_dir_re, Gem.default_dir
  end

  def test_self_default_exec_format
    orig_BASERUBY = Gem::ConfigMap[:BASERUBY]
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:RUBY_INSTALL_NAME]
    Gem::ConfigMap[:BASERUBY] = 'ruby'
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = 'ruby'

    assert_equal '%s', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:BASERUBY] = orig_BASERUBY
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_exec_format_18
    orig_BASERUBY = Gem::ConfigMap[:BASERUBY]
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:RUBY_INSTALL_NAME]
    Gem::ConfigMap[:BASERUBY] = 'ruby'
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = 'ruby18'

    assert_equal '%s18', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:BASERUBY] = orig_BASERUBY
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_exec_format_jruby
    orig_BASERUBY = Gem::ConfigMap[:BASERUBY]
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:RUBY_INSTALL_NAME]
    Gem::ConfigMap[:BASERUBY] = 'ruby'
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = 'jruby'

    assert_equal 'j%s', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:BASERUBY] = orig_BASERUBY
    Gem::ConfigMap[:RUBY_INSTALL_NAME] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_sources
    assert_equal %w[http://gems.rubyforge.org/], Gem.default_sources
  end

  def test_self_dir
    assert_equal @gemhome, Gem.dir

    Gem::DIRECTORIES.each do |filename|
      assert File.directory?(File.join(Gem.dir, filename)),
             "expected #{filename} to exist"
    end
  end

  def test_self_ensure_gem_directories
    FileUtils.rm_r @gemhome
    Gem.use_paths @gemhome

    Gem.ensure_gem_subdirectories @gemhome

    assert File.directory?(File.join(@gemhome, "cache"))
  end

  def test_self_ensure_gem_directories_missing_parents
    gemdir = File.join @tempdir, 'a/b/c/gemdir'
    FileUtils.rm_rf File.join(@tempdir, 'a') rescue nil
    assert !File.exist?(File.join(@tempdir, 'a')),
           "manually remove #{File.join @tempdir, 'a'}, tests are broken"
    Gem.use_paths gemdir

    Gem.ensure_gem_subdirectories gemdir

    assert File.directory?("#{gemdir}/cache")
  end

  unless win_platform? then # only for FS that support write protection
    def test_self_ensure_gem_directories_write_protected
      gemdir = File.join @tempdir, "egd"
      FileUtils.rm_r gemdir rescue nil
      assert !File.exist?(gemdir), "manually remove #{gemdir}, tests are broken"
      FileUtils.mkdir_p gemdir
      FileUtils.chmod 0400, gemdir
      Gem.use_paths gemdir

      Gem.ensure_gem_subdirectories gemdir

      assert !File.exist?("#{gemdir}/cache")
    ensure
      FileUtils.chmod 0600, gemdir
    end

    def test_self_ensure_gem_directories_write_protected_parents
      parent = File.join(@tempdir, "egd")
      gemdir = "#{parent}/a/b/c"

      FileUtils.rm_r parent rescue nil
      assert !File.exist?(parent), "manually remove #{parent}, tests are broken"
      FileUtils.mkdir_p parent
      FileUtils.chmod 0400, parent
      Gem.use_paths(gemdir)

      Gem.ensure_gem_subdirectories gemdir

      assert !File.exist?("#{gemdir}/cache")
    ensure
      FileUtils.chmod 0600, parent
    end
  end

  def test_ensure_ssl_available
    orig_Gem_ssl_available = Gem.ssl_available?

    Gem.ssl_available = true
    Gem.ensure_ssl_available

    Gem.ssl_available = false
    e = assert_raises Gem::Exception do Gem.ensure_ssl_available end
    assert_equal 'SSL is not installed on this system', e.message
  ensure
    Gem.ssl_available = orig_Gem_ssl_available
  end

  def test_self_find_files
    foo1 = quick_gem 'foo', '1' do |s|
      s.files << 'lib/foo/discover.rb'
    end

    foo2 = quick_gem 'foo', '2' do |s|
      s.files << 'lib/foo/discover.rb'
    end

    path = File.join 'gems', foo1.full_name, 'lib', 'foo', 'discover.rb'
    write_file(path) { |fp| fp.puts "# #{path}" }

    path = File.join 'gems', foo2.full_name, 'lib', 'foo', 'discover.rb'
    write_file(path) { |fp| fp.puts "# #{path}" }

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    Gem.source_index = util_setup_spec_fetcher foo1, foo2

    Gem.searcher = nil

    expected = [
      File.join(foo1.full_gem_path, 'lib', 'foo', 'discover.rb'),
      File.join(foo2.full_gem_path, 'lib', 'foo', 'discover.rb'),
    ]

    assert_equal expected, Gem.find_files('foo/discover').sort
  end

  def test_self_latest_load_paths
    util_make_gems

    expected = [
      File.join(@gemhome, *%W[gems #{@a2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@a_evil9.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@b2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@c1_2.full_name} lib]),
      File.join(@gemhome, *%W[gems #{@pl1.full_name} lib]),
    ]

    assert_equal expected, Gem.latest_load_paths.sort
  end

  def test_self_loaded_specs
    foo = quick_gem 'foo'
    install_gem foo
    Gem.source_index = nil

    Gem.activate 'foo'

    assert_equal true, Gem.loaded_specs.keys.include?('foo')
  end

  def test_self_path
    assert_equal [Gem.dir], Gem.path
  end

  def test_self_path_default
    if defined? APPLE_GEM_HOME
      orig_APPLE_GEM_HOME = APPLE_GEM_HOME
      Object.send :remove_const, :APPLE_GEM_HOME
    end
    Gem.instance_variable_set :@gem_path, nil

    assert_equal [Gem.default_path, Gem.dir].flatten, Gem.path
  ensure
    Object.const_set :APPLE_GEM_HOME, orig_APPLE_GEM_HOME
  end

  unless win_platform?
    def test_self_path_APPLE_GEM_HOME
      Gem.clear_paths
      apple_gem_home = File.join @tempdir, 'apple_gem_home'
      Gem.const_set :APPLE_GEM_HOME, apple_gem_home

      assert Gem.path.include?(apple_gem_home)
    ensure
      Gem.send :remove_const, :APPLE_GEM_HOME
    end

    def test_self_path_APPLE_GEM_HOME_GEM_PATH
      Gem.clear_paths
      ENV['GEM_PATH'] = @gemhome
      apple_gem_home = File.join @tempdir, 'apple_gem_home'
      Gem.const_set :APPLE_GEM_HOME, apple_gem_home

      assert !Gem.path.include?(apple_gem_home)
    ensure
      Gem.send :remove_const, :APPLE_GEM_HOME
    end
  end

  def test_self_path_ENV_PATH
    Gem.send :set_paths, nil
    path_count = Gem.path.size
    Gem.clear_paths

    ENV['GEM_PATH'] = @additional.join(File::PATH_SEPARATOR)

    assert_equal @additional, Gem.path[0,2]

    assert_equal path_count + @additional.size, Gem.path.size,
                 "extra path components: #{Gem.path[2..-1].inspect}"
    assert_equal Gem.dir, Gem.path.last
  end

  def test_self_path_duplicate
    Gem.clear_paths
    util_ensure_gem_dirs
    dirs = @additional + [@gemhome] + [File.join(@tempdir, 'a')]

    ENV['GEM_HOME'] = @gemhome
    ENV['GEM_PATH'] = dirs.join File::PATH_SEPARATOR

    assert_equal @gemhome, Gem.dir

    paths = [Gem.dir]
    assert_equal @additional + paths, Gem.path
  end

  def test_self_path_overlap
    Gem.clear_paths

    util_ensure_gem_dirs
    ENV['GEM_HOME'] = @gemhome
    ENV['GEM_PATH'] = @additional.join(File::PATH_SEPARATOR)

    assert_equal @gemhome, Gem.dir

    paths = [Gem.dir]
    assert_equal @additional + paths, Gem.path
  end

  def test_self_platforms
    assert_equal [Gem::Platform::RUBY, Gem::Platform.local], Gem.platforms
  end

  def test_self_prefix
    file_name = File.expand_path __FILE__

    prefix = File.dirname File.dirname(file_name)
    prefix = File.dirname prefix if File.basename(prefix) == 'test'

    assert_equal prefix, Gem.prefix
  end

  def test_self_prefix_libdir
    orig_libdir = Gem::ConfigMap[:libdir]

    file_name = File.expand_path __FILE__
    prefix = File.dirname File.dirname(file_name)
    prefix = File.dirname prefix if File.basename(prefix) == 'test'

    Gem::ConfigMap[:libdir] = prefix

    assert_nil Gem.prefix
  ensure
    Gem::ConfigMap[:libdir] = orig_libdir
  end

  def test_self_prefix_sitelibdir
    orig_sitelibdir = Gem::ConfigMap[:sitelibdir]

    file_name = File.expand_path __FILE__
    prefix = File.dirname File.dirname(file_name)
    prefix = File.dirname prefix if File.basename(prefix) == 'test'

    Gem::ConfigMap[:sitelibdir] = prefix

    assert_nil Gem.prefix
  ensure
    Gem::ConfigMap[:sitelibdir] = orig_sitelibdir
  end

  def test_self_refresh
    util_make_gems

    a1_spec = File.join @gemhome, "specifications", "#{@a1.full_name}.gemspec" 

    FileUtils.mv a1_spec, @tempdir

    assert !Gem.source_index.gems.include?(@a1.full_name)

    FileUtils.mv File.join(@tempdir, "#{@a1.full_name}.gemspec"), a1_spec

    Gem.refresh

    assert Gem.source_index.gems.include?(@a1.full_name)
    assert_equal nil, Gem.instance_variable_get(:@searcher)
  end

  def test_self_required_location
    util_make_gems

    assert_equal File.join(@tempdir, *%w[gemhome gems c-1.2 lib code.rb]),
                 Gem.required_location("c", "code.rb")
    assert_equal File.join(@tempdir, *%w[gemhome gems a-1 lib code.rb]),
                 Gem.required_location("a", "code.rb", "< 2")
    assert_equal File.join(@tempdir, *%w[gemhome gems a-2 lib code.rb]),
                 Gem.required_location("a", "code.rb", "= 2")
  end

  def test_self_ruby_escaping_spaces_in_path
    orig_ruby = Gem.ruby
    orig_bindir = Gem::ConfigMap[:bindir]
    orig_ruby_install_name = Gem::ConfigMap[:ruby_install_name]
    orig_exe_ext = Gem::ConfigMap[:EXEEXT]

    Gem::ConfigMap[:bindir] = "C:/Ruby 1.8/bin"
    Gem::ConfigMap[:ruby_install_name] = "ruby"
    Gem::ConfigMap[:EXEEXT] = ".exe"
    Gem.instance_variable_set("@ruby", nil)

    assert_equal "\"C:/Ruby 1.8/bin/ruby.exe\"", Gem.ruby
  ensure
    Gem.instance_variable_set("@ruby", orig_ruby)
    Gem::ConfigMap[:bindir] = orig_bindir
    Gem::ConfigMap[:ruby_install_name] = orig_ruby_install_name
    Gem::ConfigMap[:EXEEXT] = orig_exe_ext
  end

  def test_self_ruby_path_without_spaces
    orig_ruby = Gem.ruby
    orig_bindir = Gem::ConfigMap[:bindir]
    orig_ruby_install_name = Gem::ConfigMap[:ruby_install_name]
    orig_exe_ext = Gem::ConfigMap[:EXEEXT]

    Gem::ConfigMap[:bindir] = "C:/Ruby18/bin"
    Gem::ConfigMap[:ruby_install_name] = "ruby"
    Gem::ConfigMap[:EXEEXT] = ".exe"
    Gem.instance_variable_set("@ruby", nil)

    assert_equal "C:/Ruby18/bin/ruby.exe", Gem.ruby
  ensure
    Gem.instance_variable_set("@ruby", orig_ruby)
    Gem::ConfigMap[:bindir] = orig_bindir
    Gem::ConfigMap[:ruby_install_name] = orig_ruby_install_name
    Gem::ConfigMap[:EXEEXT] = orig_exe_ext
  end

  def test_self_ruby_version
    version = RUBY_VERSION.dup
    version << ".#{RUBY_PATCHLEVEL}" if defined? RUBY_PATCHLEVEL

    assert_equal Gem::Version.new(version), Gem.ruby_version
  end

  def test_self_searcher
    assert_kind_of Gem::GemPathSearcher, Gem.searcher
  end

  def test_self_source_index
    assert_kind_of Gem::SourceIndex, Gem.source_index
  end

  def test_self_sources
    assert_equal %w[http://gems.example.com/], Gem.sources
  end

  def test_ssl_available_eh
    orig_Gem_ssl_available = Gem.ssl_available?

    Gem.ssl_available = true
    assert_equal true, Gem.ssl_available?

    Gem.ssl_available = false
    assert_equal false, Gem.ssl_available?
  ensure
    Gem.ssl_available = orig_Gem_ssl_available
  end

  def test_self_use_paths
    util_ensure_gem_dirs

    Gem.use_paths @gemhome, @additional

    assert_equal @gemhome, Gem.dir
    assert_equal @additional + [Gem.dir], Gem.path
  end

  def test_self_user_dir
    assert_equal File.join(@userhome, '.gem', Gem.ruby_engine,
                           Gem::ConfigMap[:ruby_version]), Gem.user_dir
  end

  def test_self_user_home
    if ENV['HOME'] then
      assert_equal ENV['HOME'], Gem.user_home
    else
      assert true, 'count this test'
    end
  end

  def test_self_user_home_user_drive_and_path
    Gem.clear_paths

    # safe-keep env variables
    orig_home, orig_user_profile = ENV['HOME'], ENV['USERPROFILE']
    orig_user_drive, orig_user_path = ENV['HOMEDRIVE'], ENV['HOMEPATH']

    # prepare the environment
    ENV.delete('HOME')
    ENV.delete('USERPROFILE')
    ENV['HOMEDRIVE'] = 'Z:'
    ENV['HOMEPATH'] = '\\Users\\RubyUser'

    assert_equal "Z:\\Users\\RubyUser", Gem.user_home

  ensure
    ENV['HOME'] = orig_home
    ENV['USERPROFILE'] = orig_user_profile
    ENV['USERDRIVE'] = orig_user_drive
    ENV['USERPATH'] = orig_user_path
  end

  def util_ensure_gem_dirs
    Gem.ensure_gem_subdirectories @gemhome
    @additional.each do |dir|
      Gem.ensure_gem_subdirectories @gemhome
    end
  end

end

