# coding: US-ASCII
require 'rubygems/test_case'
require 'rubygems'
require 'rubygems/command'
require 'rubygems/installer'
require 'pathname'
require 'tmpdir'
require 'rbconfig'

if File.exist?(File.join(Dir.tmpdir, "Gemfile"))
  raise "rubygems/bundler tests do not work correctly if there is #{ File.join(Dir.tmpdir, "Gemfile") }"
end

# TODO: push this up to test_case.rb once battle tested

$LOAD_PATH.map! do |path|
  path.dup.tap(&Gem::UNTAINT)
end

class TestGem < Gem::TestCase

  PLUGINS_LOADED = [] # rubocop:disable Style/MutableConstant

  PROJECT_DIR = File.expand_path('../../..', __FILE__).tap(&Gem::UNTAINT)

  def setup
    super

    PLUGINS_LOADED.clear

    common_installer_setup

    ENV.delete 'RUBYGEMS_GEMDEPS'
    @additional = %w[a b].map { |d| File.join @tempdir, d }

    util_remove_interrupt_command
  end

  def test_self_finish_resolve
    save_loaded_features do
      a1 = util_spec "a", "1", "b" => "> 0"
      b1 = util_spec "b", "1", "c" => ">= 1"
      b2 = util_spec "b", "2", "c" => ">= 2"
      c1 = util_spec "c", "1"
      c2 = util_spec "c", "2"

      install_specs c1, c2, b1, b2, a1

      a1.activate

      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      Gem.finish_resolve

      assert_equal %w(a-1 b-2 c-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_self_finish_resolve_wtf
    save_loaded_features do
      a1 = util_spec "a", "1", "b" => "> 0", "d" => "> 0"    # this
      b1 = util_spec "b", "1", { "c" => ">= 1" }, "lib/b.rb" # this
      b2 = util_spec "b", "2", { "c" => ">= 2" }, "lib/b.rb"
      c1 = util_spec "c", "1"                                # this
      c2 = util_spec "c", "2"
      d1 = util_spec "d", "1", { "c" => "< 2" },  "lib/d.rb"
      d2 = util_spec "d", "2", { "c" => "< 2" },  "lib/d.rb" # this

      install_specs c1, c2, b1, b2, d1, d2, a1

      a1.activate

      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)", "d (> 0)"], unresolved_names

      Gem.finish_resolve

      assert_equal %w(a-1 b-1 c-1 d-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_self_finish_resolve_respects_loaded_specs
    save_loaded_features do
      a1 = util_spec "a", "1", "b" => "> 0"
      b1 = util_spec "b", "1", "c" => ">= 1"
      b2 = util_spec "b", "2", "c" => ">= 2"
      c1 = util_spec "c", "1"
      c2 = util_spec "c", "2"

      install_specs c1, c2, b1, b2, a1

      a1.activate
      c1.activate

      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      Gem.finish_resolve

      assert_equal %w(a-1 b-1 c-1), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_self_install
    spec_fetcher do |f|
      f.gem  'a', 1
      f.spec 'a', 2
    end

    gemhome2 = "#{@gemhome}2"

    installed = Gem.install 'a', '= 1', :install_dir => gemhome2

    assert_equal %w[a-1], installed.map { |spec| spec.full_name }

    assert_path_exists File.join(gemhome2, 'gems', 'a-1')
  end

  def test_self_install_in_rescue
    spec_fetcher do |f|
      f.gem  'a', 1
      f.spec 'a', 2
    end

    gemhome2 = "#{@gemhome}2"

    installed =
      begin
        raise 'Error'
      rescue StandardError
        Gem.install 'a', '= 1', :install_dir => gemhome2
      end
    assert_equal %w[a-1], installed.map { |spec| spec.full_name }
  end

  def test_self_install_permissions
    assert_self_install_permissions
  end

  def test_self_install_permissions_umask_0
    umask = File.umask(0)
    assert_self_install_permissions
  ensure
    File.umask(umask)
  end

  def test_self_install_permissions_umask_077
    umask = File.umask(077)
    assert_self_install_permissions
  ensure
    File.umask(umask)
  end

  def test_self_install_permissions_with_format_executable
    assert_self_install_permissions(format_executable: true)
  end

  def test_self_install_permissions_with_format_executable_and_non_standard_ruby_install_name
    Gem::Installer.exec_format = nil
    with_clean_path_to_ruby do
      ruby_install_name 'ruby27' do
        assert_self_install_permissions(format_executable: true)
      end
    end
  ensure
    Gem::Installer.exec_format = nil
  end

  def assert_self_install_permissions(format_executable: false)
    mask = win_platform? ? 0700 : 0777
    options = {
      :dir_mode => 0500,
      :prog_mode => win_platform? ? 0410 : 0510,
      :data_mode => 0640,
      :wrappers => true,
      :format_executable => format_executable
    }
    Dir.chdir @tempdir do
      Dir.mkdir 'bin'
      Dir.mkdir 'data'

      File.write 'bin/foo', "#!/usr/bin/env ruby\n"
      File.chmod 0755, 'bin/foo'

      File.write 'data/foo.txt', "blah\n"

      spec_fetcher do |f|
        f.gem 'foo', 1 do |s|
          s.executables = ['foo']
          s.files = %w[bin/foo data/foo.txt]
        end
      end
      Gem.install 'foo', Gem::Requirement.default, options
    end

    prog_mode = (options[:prog_mode] & mask).to_s(8)
    dir_mode = (options[:dir_mode] & mask).to_s(8)
    data_mode = (options[:data_mode] & mask).to_s(8)
    prog_name = 'foo'
    prog_name = RbConfig::CONFIG['ruby_install_name'].sub('ruby', 'foo') if options[:format_executable]
    expected = {
      "bin/#{prog_name}" => prog_mode,
      'gems/foo-1' => dir_mode,
      'gems/foo-1/bin' => dir_mode,
      'gems/foo-1/data' => dir_mode,
      'gems/foo-1/bin/foo' => prog_mode,
      'gems/foo-1/data/foo.txt' => data_mode,
    }
    # add Windows script
    expected["bin/#{prog_name}.bat"] = mask.to_s(8) if win_platform?
    result = {}
    Dir.chdir @gemhome do
      expected.each_key do |n|
        result[n] = (File.stat(n).mode & mask).to_s(8)
      end
    end
    assert_equal(expected, result)
  ensure
    File.chmod(0755, *Dir.glob(@gemhome + '/gems/**/').map {|path| path.tap(&Gem::UNTAINT)})
  end

  def test_require_missing
    save_loaded_features do
      assert_raises ::LoadError do
        require "q"
      end
    end
  end

  def test_require_does_not_glob
    save_loaded_features do
      a1 = util_spec "a", "1", nil, "lib/a1.rb"

      install_specs a1

      assert_raises ::LoadError do
        require "a*"
      end

      assert_equal [], loaded_spec_names
    end
  end

  def test_self_bin_path_active
    a1 = util_spec 'a', '1' do |s|
      s.executables = ['exec']
    end

    util_spec 'a', '2' do |s|
      s.executables = ['exec']
    end

    a1.activate

    assert_match 'a-1/bin/exec', Gem.bin_path('a', 'exec', '>= 0')
  end

  def test_self_bin_path_picking_newest
    a1 = util_spec 'a', '1' do |s|
      s.executables = ['exec']
    end

    a2 = util_spec 'a', '2' do |s|
      s.executables = ['exec']
    end

    install_specs a1, a2

    assert_match 'a-2/bin/exec', Gem.bin_path('a', 'exec', '>= 0')
  end

  def test_self_activate_bin_path_no_exec_name
    e = assert_raises ArgumentError do
      Gem.activate_bin_path 'a'
    end

    assert_equal 'you must supply exec_name', e.message
  end

  def test_activate_bin_path_resolves_eagerly
    a1 = util_spec 'a', '1' do |s|
      s.executables = ['exec']
      s.add_dependency 'b'
    end

    b1 = util_spec 'b', '1' do |s|
      s.add_dependency 'c', '2'
    end

    b2 = util_spec 'b', '2' do |s|
      s.add_dependency 'c', '1'
    end

    c1 = util_spec 'c', '1'
    c2 = util_spec 'c', '2'

    install_specs c1, c2, b1, b2, a1

    Gem.activate_bin_path("a", "exec", ">= 0")

    # If we didn't eagerly resolve, this would activate c-2 and then the
    # finish_resolve would cause a conflict
    gem 'c'
    Gem.finish_resolve

    assert_equal %w(a-1 b-2 c-1), loaded_spec_names
  end

  def test_activate_bin_path_gives_proper_error_for_bundler
    bundler = util_spec 'bundler', '2' do |s|
      s.executables = ['bundle']
    end

    install_specs bundler

    File.open("Gemfile.lock", "w") do |f|
      f.write <<-L.gsub(/ {8}/, "")
        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES

        BUNDLED WITH
          9999
      L
    end

    File.open("Gemfile", "w") { |f| f.puts('source "https://rubygems.org"') }

    e = assert_raises Gem::GemNotFoundException do
      load Gem.activate_bin_path("bundler", "bundle", ">= 0.a")
    end

    assert_includes e.message, "Could not find 'bundler' (9999) required by your #{File.expand_path("Gemfile.lock")}."
    assert_includes e.message, "To update to the latest version installed on your system, run `bundle update --bundler`."
    assert_includes e.message, "To install the missing version, run `gem install bundler:9999`"
    refute_includes e.message, "can't find gem bundler (>= 0.a) with executable bundle"
  end

  def test_activate_bin_path_selects_exact_bundler_version_if_present
    bundler_latest = util_spec 'bundler', '2.0.1' do |s|
      s.executables = ['bundle']
    end

    bundler_previous = util_spec 'bundler', '2.0.0' do |s|
      s.executables = ['bundle']
    end

    install_specs bundler_latest, bundler_previous

    File.open("Gemfile.lock", "w") do |f|
      f.write <<-L.gsub(/ {8}/, "")
        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES

        BUNDLED WITH
          2.0.0
      L
    end

    File.open("Gemfile", "w") { |f| f.puts('source "https://rubygems.org"') }

    load Gem.activate_bin_path("bundler", "bundle", ">= 0.a")

    assert_equal %w(bundler-2.0.0), loaded_spec_names
  end

  def test_activate_bin_path_respects_underscore_selection_if_given
    bundler_latest = util_spec 'bundler', '2.0.1' do |s|
      s.executables = ['bundle']
    end

    bundler_previous = util_spec 'bundler', '1.17.3' do |s|
      s.executables = ['bundle']
    end

    install_specs bundler_latest, bundler_previous

    File.open("Gemfile.lock", "w") do |f|
      f.write <<-L.gsub(/ {8}/, "")
        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES

        BUNDLED WITH
          2.0.1
      L
    end

    File.open("Gemfile", "w") { |f| f.puts('source "https://rubygems.org"') }

    load Gem.activate_bin_path("bundler", "bundle", "= 1.17.3")

    assert_equal %w(bundler-1.17.3), loaded_spec_names
  end

  def test_self_bin_path_no_exec_name
    e = assert_raises ArgumentError do
      Gem.bin_path 'a'
    end

    assert_equal 'you must supply exec_name', e.message
  end

  def test_self_bin_path_bin_name
    install_specs util_exec_gem
    assert_equal @abin_path, Gem.bin_path('a', 'abin')
  end

  def test_self_bin_path_bin_name_version
    install_specs util_exec_gem
    assert_equal @abin_path, Gem.bin_path('a', 'abin', '4')
  end

  def test_self_bin_path_nonexistent_binfile
    util_spec 'a', '2' do |s|
      s.executables = ['exec']
    end
    assert_raises(Gem::GemNotFoundException) do
      Gem.bin_path('a', 'other', '2')
    end
  end

  def test_self_bin_path_no_bin_file
    util_spec 'a', '1'
    assert_raises(ArgumentError) do
      Gem.bin_path('a', nil, '1')
    end
  end

  def test_self_bin_path_not_found
    assert_raises(Gem::GemNotFoundException) do
      Gem.bin_path('non-existent', 'blah')
    end
  end

  def test_self_bin_path_bin_file_gone_in_latest
    install_specs util_exec_gem
    spec = util_spec 'a', '10' do |s|
      s.executables = []
    end
    install_specs spec
    # Should not find a-10's non-abin (bug)
    assert_equal @abin_path, Gem.bin_path('a', 'abin')
  end

  def test_self_bindir
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir(Gem.dir)
    assert_equal File.join(@gemhome, 'bin'), Gem.bindir(Pathname.new(Gem.dir))
  end

  def test_self_bindir_default_dir
    default = Gem.default_dir

    assert_equal Gem.default_bindir, Gem.bindir(default)
  end

  def test_self_clear_paths
    assert_match(/gemhome$/, Gem.dir)
    assert_match(/gemhome$/, Gem.path.first)

    Gem.clear_paths

    assert_nil Gem::Specification.send(:class_variable_get, :@@all)
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

      foo = util_spec 'foo' do |s|
        s.files = %w[data/foo.txt]
      end

      install_gem foo
    end

    gem 'foo'

    expected = File.join @gemhome, 'gems', foo.full_name, 'data', 'foo'

    assert_equal expected, Gem::Specification.find_by_name("foo").datadir
  end

  def test_self_datadir_nonexistent_package
    assert_raises(Gem::MissingSpecError) do
      Gem::Specification.find_by_name("xyzzy").datadir
    end
  end

  def test_self_default_exec_format
    ruby_install_name 'ruby' do
      assert_equal '%s', Gem.default_exec_format
    end
  end

  def test_self_default_exec_format_18
    ruby_install_name 'ruby18' do
      assert_equal '%s18', Gem.default_exec_format
    end
  end

  def test_self_default_exec_format_jruby
    ruby_install_name 'jruby' do
      assert_equal 'j%s', Gem.default_exec_format
    end
  end

  def test_default_path
    vendordir(File.join(@tempdir, 'vendor')) do
      FileUtils.rm_rf Gem.user_home

      expected = [Gem.default_dir]

      assert_equal expected, Gem.default_path
    end
  end

  def test_default_path_missing_vendor
    vendordir(nil) do
      FileUtils.rm_rf Gem.user_home

      expected = [Gem.default_dir]

      assert_equal expected, Gem.default_path
    end
  end

  def test_default_path_user_home
    vendordir(File.join(@tempdir, 'vendor')) do
      expected = [Gem.user_dir, Gem.default_dir]

      assert_equal expected, Gem.default_path
    end
  end

  def test_default_path_vendor_dir
    vendordir(File.join(@tempdir, 'vendor')) do
      FileUtils.mkdir_p Gem.vendor_dir

      FileUtils.rm_rf Gem.user_home

      expected = [Gem.default_dir, Gem.vendor_dir]

      assert_equal expected, Gem.default_path
    end
  end

  def test_self_default_sources
    assert_equal %w[https://rubygems.org/], Gem.default_sources
  end

  def test_self_use_gemdeps
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], '-'

    FileUtils.mkdir_p 'detect/a/b'
    FileUtils.mkdir_p 'detect/a/Isolate'

    FileUtils.touch 'detect/Isolate'

    begin
      Dir.chdir 'detect/a/b'

      assert_equal add_bundler_full_name([]), Gem.use_gemdeps.map(&:full_name)
    ensure
      Dir.chdir @tempdir
    end
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_self_dir
    assert_equal @gemhome, Gem.dir
  end

  def test_self_ensure_gem_directories
    FileUtils.rm_r @gemhome
    Gem.use_paths @gemhome

    Gem.ensure_gem_subdirectories @gemhome

    assert_path_exists File.join @gemhome, 'build_info'
    assert_path_exists File.join @gemhome, 'cache'
    assert_path_exists File.join @gemhome, 'doc'
    assert_path_exists File.join @gemhome, 'extensions'
    assert_path_exists File.join @gemhome, 'gems'
    assert_path_exists File.join @gemhome, 'specifications'
  end

  def test_self_ensure_gem_directories_permissions
    FileUtils.rm_r @gemhome
    Gem.use_paths @gemhome

    Gem.ensure_gem_subdirectories @gemhome, 0750

    assert_directory_exists File.join(@gemhome, "cache")

    assert_equal 0750, File::Stat.new(@gemhome).mode & 0777
    assert_equal 0750, File::Stat.new(File.join(@gemhome, "cache")).mode & 0777
  end unless win_platform?

  def test_self_ensure_gem_directories_safe_permissions
    FileUtils.rm_r @gemhome
    Gem.use_paths @gemhome

    old_umask = File.umask
    File.umask 0
    Gem.ensure_gem_subdirectories @gemhome

    assert_equal 0, File::Stat.new(@gemhome).mode & 002
    assert_equal 0, File::Stat.new(File.join(@gemhome, "cache")).mode & 002
  ensure
    File.umask old_umask
  end unless win_platform?

  def test_self_ensure_gem_directories_missing_parents
    gemdir = File.join @tempdir, 'a/b/c/gemdir'
    FileUtils.rm_rf File.join(@tempdir, 'a') rescue nil
    refute File.exist?(File.join(@tempdir, 'a')),
           "manually remove #{File.join @tempdir, 'a'}, tests are broken"
    Gem.use_paths gemdir

    Gem.ensure_gem_subdirectories gemdir

    assert_directory_exists util_cache_dir
  end

  unless win_platform? || Process.uid.zero?  # only for FS that support write protection
    def test_self_ensure_gem_directories_write_protected
      gemdir = File.join @tempdir, "egd"
      FileUtils.rm_r gemdir rescue nil
      refute File.exist?(gemdir), "manually remove #{gemdir}, tests are broken"
      FileUtils.mkdir_p gemdir
      FileUtils.chmod 0400, gemdir
      Gem.use_paths gemdir

      Gem.ensure_gem_subdirectories gemdir

      refute File.exist?(util_cache_dir)
    ensure
      FileUtils.chmod 0600, gemdir
    end

    def test_self_ensure_gem_directories_write_protected_parents
      parent = File.join(@tempdir, "egd")
      gemdir = "#{parent}/a/b/c"

      FileUtils.rm_r parent rescue nil
      refute File.exist?(parent), "manually remove #{parent}, tests are broken"
      FileUtils.mkdir_p parent
      FileUtils.chmod 0400, parent
      Gem.use_paths(gemdir)

      Gem.ensure_gem_subdirectories gemdir

      refute File.exist? File.join(gemdir, "gems")
    ensure
      FileUtils.chmod 0600, parent
    end
  end

  def test_self_extension_dir_shared
    enable_shared 'yes' do
      assert_equal Gem.ruby_api_version, Gem.extension_api_version
    end
  end

  def test_self_extension_dir_static
    enable_shared 'no' do
      assert_equal "#{Gem.ruby_api_version}-static", Gem.extension_api_version
    end
  end

  def test_self_find_files
    cwd = File.expand_path("test/rubygems", PROJECT_DIR)
    $LOAD_PATH.unshift cwd

    discover_path = File.join 'lib', 'sff', 'discover.rb'

    foo1, foo2 = %w(1 2).map do |version|
      spec = quick_gem 'sff', version do |s|
        s.files << discover_path
      end

      write_file(File.join 'gems', spec.full_name, discover_path) do |fp|
        fp.puts "# #{spec.full_name}"
      end

      spec
    end

    Gem.refresh

    expected = [
      File.expand_path('test/rubygems/sff/discover.rb', PROJECT_DIR),
      File.join(foo2.full_gem_path, discover_path),
      File.join(foo1.full_gem_path, discover_path),
    ]

    assert_equal expected, Gem.find_files('sff/discover')
    assert_equal expected, Gem.find_files('sff/**.rb'), '[ruby-core:31730]'
  ensure
    assert_equal cwd, $LOAD_PATH.shift
  end

  def test_self_find_files_with_gemfile
    cwd = File.expand_path("test/rubygems", PROJECT_DIR)
    actual_load_path = $LOAD_PATH.unshift(cwd).dup

    discover_path = File.join 'lib', 'sff', 'discover.rb'

    foo1, _ = %w(1 2).map do |version|
      spec = quick_gem 'sff', version do |s|
        s.files << discover_path
      end

      write_file(File.join 'gems', spec.full_name, discover_path) do |fp|
        fp.puts "# #{spec.full_name}"
      end

      spec
    end
    Gem.refresh

    write_file(File.join Dir.pwd, 'Gemfile') do |fp|
      fp.puts "source 'https://rubygems.org'"
      fp.puts "gem '#{foo1.name}', '#{foo1.version}'"
    end
    Gem.use_gemdeps(File.join Dir.pwd, 'Gemfile')

    expected = [
      File.expand_path('test/rubygems/sff/discover.rb', PROJECT_DIR),
      File.join(foo1.full_gem_path, discover_path)
    ].sort

    assert_equal expected, Gem.find_files('sff/discover').sort
    assert_equal expected, Gem.find_files('sff/**.rb').sort, '[ruby-core:31730]'
  ensure
    assert_equal cwd, actual_load_path.shift unless Gem.java_platform?
  end

  def test_self_find_latest_files
    cwd = File.expand_path("test/rubygems", PROJECT_DIR)
    $LOAD_PATH.unshift cwd

    discover_path = File.join 'lib', 'sff', 'discover.rb'

    _, foo2 = %w(1 2).map do |version|
      spec = quick_gem 'sff', version do |s|
        s.files << discover_path
      end

      write_file(File.join 'gems', spec.full_name, discover_path) do |fp|
        fp.puts "# #{spec.full_name}"
      end

      spec
    end

    Gem.refresh

    expected = [
      File.expand_path('test/rubygems/sff/discover.rb', PROJECT_DIR),
      File.join(foo2.full_gem_path, discover_path),
    ]

    assert_equal expected, Gem.find_latest_files('sff/discover')
    assert_equal expected, Gem.find_latest_files('sff/**.rb'), '[ruby-core:31730]'
  ensure
    assert_equal cwd, $LOAD_PATH.shift
  end

  def test_self_latest_spec_for
    gems = spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '3.a'
      fetcher.spec 'a', 2
    end

    spec = Gem.latest_spec_for 'a'

    assert_equal gems['a-2'], spec
  end

  def test_self_latest_rubygems_version
    spec_fetcher do |fetcher|
      fetcher.spec 'rubygems-update', '1.8.23'
      fetcher.spec 'rubygems-update', '1.8.24'
      fetcher.spec 'rubygems-update', '2.0.0.preview3'
    end

    version = Gem.latest_rubygems_version

    assert_equal Gem::Version.new('1.8.24'), version
  end

  def test_self_latest_version_for
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
    end

    version = Gem.latest_version_for 'a'

    assert_equal Gem::Version.new(2), version
  end

  def test_self_loaded_specs
    foo = util_spec 'foo'
    install_gem foo

    foo.activate

    assert_equal true, Gem.loaded_specs.keys.include?('foo')
  end

  def util_path
    ENV.delete "GEM_HOME"
    ENV.delete "GEM_PATH"
  end

  def test_self_path
    assert_equal [Gem.dir], Gem.path
  end

  def test_self_path_default
    util_path

    if defined?(APPLE_GEM_HOME)
      orig_APPLE_GEM_HOME = APPLE_GEM_HOME
      Object.send :remove_const, :APPLE_GEM_HOME
    end

    Gem.instance_variable_set :@paths, nil

    assert_equal [Gem.default_path, Gem.dir].flatten.uniq, Gem.path
  ensure
    Object.const_set :APPLE_GEM_HOME, orig_APPLE_GEM_HOME if orig_APPLE_GEM_HOME
  end

  unless win_platform?
    def test_self_path_APPLE_GEM_HOME
      util_path

      Gem.clear_paths
      apple_gem_home = File.join @tempdir, 'apple_gem_home'

      old, $-w = $-w, nil
      Object.const_set :APPLE_GEM_HOME, apple_gem_home
      $-w = old

      assert_includes Gem.path, apple_gem_home
    ensure
      Object.send :remove_const, :APPLE_GEM_HOME
    end

    def test_self_path_APPLE_GEM_HOME_GEM_PATH
      Gem.clear_paths
      ENV['GEM_PATH'] = @gemhome
      apple_gem_home = File.join @tempdir, 'apple_gem_home'
      Gem.const_set :APPLE_GEM_HOME, apple_gem_home

      refute Gem.path.include?(apple_gem_home)
    ensure
      Gem.send :remove_const, :APPLE_GEM_HOME
    end
  end

  def test_self_path_ENV_PATH
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
    assert_equal PROJECT_DIR, Gem.prefix
  end

  def test_self_prefix_libdir
    orig_libdir = RbConfig::CONFIG['libdir']
    RbConfig::CONFIG['libdir'] = PROJECT_DIR

    assert_nil Gem.prefix
  ensure
    RbConfig::CONFIG['libdir'] = orig_libdir
  end

  def test_self_prefix_sitelibdir
    orig_sitelibdir = RbConfig::CONFIG['sitelibdir']
    RbConfig::CONFIG['sitelibdir'] = PROJECT_DIR

    assert_nil Gem.prefix
  ensure
    RbConfig::CONFIG['sitelibdir'] = orig_sitelibdir
  end

  def test_self_read_binary
    File.open 'test', 'w' do |io|
      io.write "\xCF\x80"
    end

    assert_equal ["\xCF", "\x80"], Gem.read_binary('test').chars.to_a

    skip 'chmod not supported' if Gem.win_platform?

    begin
      File.chmod 0444, 'test'

      assert_equal ["\xCF", "\x80"], Gem.read_binary('test').chars.to_a
    ensure
      File.chmod 0644, 'test'
    end
  end

  def test_self_refresh
    util_make_gems

    a1_spec = @a1.spec_file
    moved_path = File.join @tempdir, File.basename(a1_spec)

    FileUtils.mv a1_spec, moved_path

    Gem.refresh

    refute_includes Gem::Specification.all_names, @a1.full_name

    FileUtils.mv moved_path, a1_spec

    Gem.refresh

    assert_includes Gem::Specification.all_names, @a1.full_name
  end

  def test_self_refresh_keeps_loaded_specs_activated
    util_make_gems

    a1_spec = @a1.spec_file
    moved_path = File.join @tempdir, File.basename(a1_spec)

    FileUtils.mv a1_spec, moved_path

    Gem.refresh

    s = Gem::Specification.first
    s.activate

    Gem.refresh

    Gem::Specification.each{|spec| assert spec.activated? if spec == s}

    Gem.loaded_specs.delete(s)
    Gem.refresh
  end

  def test_self_ruby_escaping_spaces_in_path
    with_clean_path_to_ruby do
      with_bindir_and_exeext("C:/Ruby 1.8/bin", ".exe") do
        ruby_install_name "ruby" do
          assert_equal "\"C:/Ruby 1.8/bin/ruby.exe\"", Gem.ruby
        end
      end
    end
  end

  def test_self_ruby_path_without_spaces
    with_clean_path_to_ruby do
      with_bindir_and_exeext("C:/Ruby18/bin", ".exe") do
        ruby_install_name "ruby" do
          assert_equal "C:/Ruby18/bin/ruby.exe", Gem.ruby
        end
      end
    end
  end

  def test_self_ruby_api_version
    orig_ruby_version, RbConfig::CONFIG['ruby_version'] = RbConfig::CONFIG['ruby_version'], '1.2.3'

    Gem.instance_variable_set :@ruby_api_version, nil

    assert_equal '1.2.3', Gem.ruby_api_version
  ensure
    Gem.instance_variable_set :@ruby_api_version, nil

    RbConfig::CONFIG['ruby_version'] = orig_ruby_version
  end

  def test_self_env_requirement
    ENV["GEM_REQUIREMENT_FOO"] = '>= 1.2.3'
    ENV["GEM_REQUIREMENT_BAR"] = '1.2.3'
    ENV["GEM_REQUIREMENT_BAZ"] = 'abcd'

    assert_equal Gem::Requirement.create('>= 1.2.3'), Gem.env_requirement('foo')
    assert_equal Gem::Requirement.create('1.2.3'), Gem.env_requirement('bAr')
    assert_raises(Gem::Requirement::BadRequirementError) { Gem.env_requirement('baz') }
    assert_equal Gem::Requirement.default, Gem.env_requirement('qux')
  end

  def test_self_ruby_version_with_patchlevel_less_ancient_rubies
    util_set_RUBY_VERSION '1.8.5'

    assert_equal Gem::Version.new('1.8.5'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_with_release
    util_set_RUBY_VERSION '1.8.6', 287

    assert_equal Gem::Version.new('1.8.6.287'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_with_non_mri_implementations
    util_set_RUBY_VERSION '2.5.0', 0, 60928, 'jruby 9.2.0.0 (2.5.0) 2018-05-24 81156a8 OpenJDK 64-Bit Server VM 25.171-b11 on 1.8.0_171-8u171-b11-0ubuntu0.16.04.1-b11 [linux-x86_64]'

    assert_equal Gem::Version.new('2.5.0'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_with_prerelease
    util_set_RUBY_VERSION '2.6.0', -1, 63539, 'ruby 2.6.0preview2 (2018-05-31 trunk 63539) [x86_64-linux]'

    assert_equal Gem::Version.new('2.6.0.preview2'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_with_non_mri_implementations_with_mri_prerelase_compatibility
    util_set_RUBY_VERSION '2.6.0', -1, 63539, 'weirdjruby 9.2.0.0 (2.6.0preview2) 2018-05-24 81156a8 OpenJDK 64-Bit Server VM 25.171-b11 on 1.8.0_171-8u171-b11-0ubuntu0.16.04.1-b11 [linux-x86_64]', 'weirdjruby', '9.2.0.0'

    assert_equal Gem::Version.new('2.6.0.preview2'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_with_trunk
    util_set_RUBY_VERSION '1.9.2', -1, 23493, 'ruby 1.9.2dev (2009-05-20 trunk 23493) [x86_64-linux]'

    assert_equal Gem::Version.new('1.9.2.dev'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_rubygems_version
    assert_equal Gem::Version.new(Gem::VERSION), Gem.rubygems_version
  end

  def test_self_paths_eq
    other = File.join @tempdir, 'other'
    path = [@userhome, other].join File::PATH_SEPARATOR

    #
    # FIXME remove after fixing test_case
    #
    ENV["GEM_HOME"] = @gemhome
    Gem.paths = { "GEM_PATH" => path }

    assert_equal [@userhome, other, @gemhome], Gem.path
  end

  def test_self_paths_eq_nonexistent_home
    ENV['GEM_HOME'] = @gemhome
    Gem.clear_paths

    other = File.join @tempdir, 'other'

    ENV['HOME'] = other

    Gem.paths = { "GEM_PATH" => other }

    assert_equal [other, @gemhome], Gem.path
  end

  def test_self_post_build
    assert_equal 1, Gem.post_build_hooks.length

    Gem.post_build { |installer| }

    assert_equal 2, Gem.post_build_hooks.length
  end

  def test_self_post_install
    assert_equal 1, Gem.post_install_hooks.length

    Gem.post_install { |installer| }

    assert_equal 2, Gem.post_install_hooks.length
  end

  def test_self_done_installing
    assert_empty Gem.done_installing_hooks

    Gem.done_installing { |gems| }

    assert_equal 1, Gem.done_installing_hooks.length
  end

  def test_self_post_reset
    assert_empty Gem.post_reset_hooks

    Gem.post_reset { }

    assert_equal 1, Gem.post_reset_hooks.length
  end

  def test_self_post_uninstall
    assert_equal 1, Gem.post_uninstall_hooks.length

    Gem.post_uninstall { |installer| }

    assert_equal 2, Gem.post_uninstall_hooks.length
  end

  def test_self_pre_install
    assert_equal 1, Gem.pre_install_hooks.length

    Gem.pre_install { |installer| }

    assert_equal 2, Gem.pre_install_hooks.length
  end

  def test_self_pre_reset
    assert_empty Gem.pre_reset_hooks

    Gem.pre_reset { }

    assert_equal 1, Gem.pre_reset_hooks.length
  end

  def test_self_pre_uninstall
    assert_equal 1, Gem.pre_uninstall_hooks.length

    Gem.pre_uninstall { |installer| }

    assert_equal 2, Gem.pre_uninstall_hooks.length
  end

  def test_self_sources
    assert_equal %w[http://gems.example.com/], Gem.sources
    Gem.sources = nil
    Gem.configuration.sources = %w[http://test.example.com/]
    assert_equal %w[http://test.example.com/], Gem.sources
  end

  def test_try_activate_returns_true_for_activated_specs
    b = util_spec 'b', '1.0' do |spec|
      spec.files << 'lib/b.rb'
    end
    install_specs b

    assert Gem.try_activate('b'), 'try_activate should return true'
    assert Gem.try_activate('b'), 'try_activate should still return true'
  end

  def test_spec_order_is_consistent
    b1 = util_spec 'b', '1.0'
    b2 = util_spec 'b', '2.0'
    b3 = util_spec 'b', '3.0'

    install_specs b1, b2, b3

    specs1 = Gem::Specification.stubs.find_all { |s| s.name == 'b' }
    Gem::Specification.reset
    specs2 = Gem::Specification.stubs_for('b')
    assert_equal specs1.map(&:version), specs2.map(&:version)
  end

  def test_self_try_activate_missing_dep
    b = util_spec 'b', '1.0'
    a = util_spec 'a', '1.0', 'b' => '>= 1.0'

    install_specs b, a
    uninstall_gem b

    a_file = File.join a.gem_dir, 'lib', 'a_file.rb'

    write_file a_file do |io|
      io.puts '# a_file.rb'
    end

    e = assert_raises Gem::MissingSpecError do
      Gem.try_activate 'a_file'
    end

    assert_match %r%Could not find 'b' %, e.message
  end

  def test_self_try_activate_missing_prerelease
    b = util_spec 'b', '1.0rc1'
    a = util_spec 'a', '1.0rc1', 'b' => '1.0rc1'

    install_specs b, a
    uninstall_gem b

    a_file = File.join a.gem_dir, 'lib', 'a_file.rb'

    write_file a_file do |io|
      io.puts '# a_file.rb'
    end

    e = assert_raises Gem::MissingSpecError do
      Gem.try_activate 'a_file'
    end

    assert_match %r%Could not find 'b' \(= 1.0rc1\)%, e.message
  end

  def test_self_try_activate_missing_extensions
    spec = util_spec 'ext', '1' do |s|
      s.extensions = %w[ext/extconf.rb]
      s.mark_version
      s.installed_by_version = v('2.2')
    end

    # write the spec without install to simulate a failed install
    write_file spec.spec_file do |io|
      io.write spec.to_ruby_for_cache
    end

    _, err = capture_io do
      refute Gem.try_activate 'nonexistent'
    end

    unless Gem.java_platform?
      expected = "Ignoring ext-1 because its extensions are not built. " +
                 "Try: gem pristine ext --version 1\n"

      assert_equal expected, err
    end
  end

  def test_self_use_paths_with_nils
    orig_home = ENV.delete 'GEM_HOME'
    orig_path = ENV.delete 'GEM_PATH'
    Gem.use_paths nil, nil
    assert_equal Gem.default_dir, Gem.paths.home
    path = (Gem.default_path + [Gem.paths.home]).uniq
    assert_equal path, Gem.paths.path
  ensure
    ENV['GEM_HOME'] = orig_home
    ENV['GEM_PATH'] = orig_path
  end

  def test_setting_paths_does_not_warn_about_unknown_keys
    stdout, stderr = capture_io do
      Gem.paths = { 'foo'      => [],
                    'bar'      => Object.new,
                    'GEM_HOME' => Gem.paths.home,
                    'GEM_PATH' => 'foo' }
    end
    assert_equal ['foo', Gem.paths.home], Gem.paths.path
    assert_equal '', stderr
    assert_equal '', stdout
  end

  def test_setting_paths_does_not_mutate_parameter_object
    Gem.paths = { 'GEM_HOME' => Gem.paths.home,
                  'GEM_PATH' => 'foo' }.freeze
    assert_equal ['foo', Gem.paths.home], Gem.paths.path
  end

  def test_deprecated_paths=
    stdout, stderr = capture_io do
      Gem.paths = { 'GEM_HOME' => Gem.paths.home,
                    'GEM_PATH' => [Gem.paths.home, 'foo'] }
    end
    assert_equal [Gem.paths.home, 'foo'], Gem.paths.path
    assert_match(/Array values in the parameter to `Gem.paths=` are deprecated.\nPlease use a String or nil/m, stderr)
    assert_equal '', stdout
  end

  def test_self_use_paths
    util_ensure_gem_dirs

    Gem.use_paths @gemhome, @additional

    assert_equal @gemhome, Gem.dir
    assert_equal @additional + [Gem.dir], Gem.path
  end

  def test_self_user_dir
    parts = [@userhome, '.gem', Gem.ruby_engine]
    parts << RbConfig::CONFIG['ruby_version'] unless RbConfig::CONFIG['ruby_version'].empty?

    assert_equal File.join(parts), Gem.user_dir
  end

  def test_self_user_home
    if ENV['HOME']
      assert_equal ENV['HOME'], Gem.user_home
    else
      assert true, 'count this test'
    end
  end

  def test_self_needs
    a = util_spec "a", "1"
    b = util_spec "b", "1", "c" => nil
    c = util_spec "c", "2"

    install_specs a, c, b

    Gem.needs do |r|
      r.gem "a"
      r.gem "b", "= 1"
    end

    activated = Gem::Specification.map { |x| x.full_name }

    assert_equal %w!a-1 b-1 c-2!, activated.sort
  end

  def test_self_needs_picks_up_unresolved_deps
    save_loaded_features do
      a = util_spec "a", "1"
      b = util_spec "b", "1", "c" => nil
      c = util_spec "c", "2"
      d = util_spec "d", "1", {'e' => '= 1'}, "lib/d.rb"
      e = util_spec "e", "1"

      install_specs a, c, b, e, d

      Gem.needs do |r|
        r.gem "a"
        r.gem "b", "= 1"

        require 'd'
      end

      assert_equal %w!a-1 b-1 c-2 d-1 e-1!, loaded_spec_names
    end
  end

  def test_self_gunzip
    input = "\x1F\x8B\b\0\xED\xA3\x1AQ\0\x03\xCBH" +
            "\xCD\xC9\xC9\a\0\x86\xA6\x106\x05\0\0\0"

    output = Gem::Util.gunzip input

    assert_equal 'hello', output
    assert_equal Encoding::BINARY, output.encoding
  end

  def test_self_gzip
    input = 'hello'

    output = Gem::Util.gzip input

    zipped = StringIO.new output

    assert_equal 'hello', Zlib::GzipReader.new(zipped).read
    assert_equal Encoding::BINARY, output.encoding
  end

  def test_self_vendor_dir
    vendordir(File.join(@tempdir, 'vendor')) do
      expected =
        File.join RbConfig::CONFIG['vendordir'], 'gems',
                  RbConfig::CONFIG['ruby_version']

      assert_equal expected, Gem.vendor_dir
    end
  end

  def test_self_vendor_dir_ENV_GEM_VENDOR
    ENV['GEM_VENDOR'] = File.join @tempdir, 'vendor', 'gems'

    assert_equal ENV['GEM_VENDOR'], Gem.vendor_dir
    refute Gem.vendor_dir.frozen?
  end

  def test_self_vendor_dir_missing
    vendordir(nil) do
      assert_nil Gem.vendor_dir
    end
  end

  def test_load_plugins
    plugin_path = File.join "lib", "rubygems_plugin.rb"

    Dir.chdir @tempdir do
      FileUtils.mkdir_p 'lib'
      File.open plugin_path, "w" do |fp|
        fp.puts "class TestGem; PLUGINS_LOADED << 'plugin'; end"
      end

      foo1 = util_spec 'foo', '1' do |s|
        s.files << plugin_path
      end

      install_gem foo1

      foo2 = util_spec 'foo', '2' do |s|
        s.files << plugin_path
      end

      install_gem foo2
    end

    Gem.searcher = nil
    Gem::Specification.reset

    gem 'foo'

    Gem.load_plugins

    assert_equal %w[plugin], PLUGINS_LOADED
  end

  def test_load_env_plugins
    with_plugin('load') { Gem.load_env_plugins }
    assert_equal :loaded, TEST_PLUGIN_LOAD rescue nil

    util_remove_interrupt_command

    # Should attempt to cause a StandardError
    with_plugin('standarderror') { Gem.load_env_plugins }
    assert_equal :loaded, TEST_PLUGIN_STANDARDERROR rescue nil

    util_remove_interrupt_command

    # Should attempt to cause an Exception
    with_plugin('exception') { Gem.load_env_plugins }
    assert_equal :loaded, TEST_PLUGIN_EXCEPTION rescue nil
  end

  def test_gem_path_ordering
    refute_equal Gem.dir, Gem.user_dir

    write_file File.join(@tempdir, 'lib', "g.rb") { |fp| fp.puts "" }
    write_file File.join(@tempdir, 'lib', 'm.rb') { |fp| fp.puts "" }

    g = util_spec 'g', '1', nil, "lib/g.rb"
    m = util_spec 'm', '1', nil, "lib/m.rb"

    install_gem g, :install_dir => Gem.dir
    m0 = install_gem m, :install_dir => Gem.dir
    m1 = install_gem m, :install_dir => Gem.user_dir

    assert_equal m0.gem_dir, File.join(Gem.dir, "gems", "m-1")
    assert_equal m1.gem_dir, File.join(Gem.user_dir, "gems", "m-1")

    tests = [
      [:dir0, [ Gem.dir, Gem.user_dir], m0],
      [:dir1, [ Gem.user_dir, Gem.dir], m1]
    ]

    tests.each do |_name, _paths, expected|
      Gem.use_paths _paths.first, _paths
      Gem::Specification.reset
      Gem.searcher = nil

      assert_equal Gem::Dependency.new('m','1').to_specs,
                   Gem::Dependency.new('m','1').to_specs.sort

      assert_equal \
        [expected.gem_dir],
        Gem::Dependency.new('m','1').to_specs.map(&:gem_dir).sort,
        "Wrong specs for #{_name}"

      spec = Gem::Dependency.new('m','1').to_spec

      assert_equal \
        File.join(_paths.first, "gems", "m-1"),
        spec.gem_dir,
        "Wrong spec before require for #{_name}"
      refute spec.activated?, "dependency already activated for #{_name}"

      gem "m"

      spec = Gem::Dependency.new('m','1').to_spec
      assert spec.activated?, "dependency not activated for #{_name}"

      assert_equal \
        File.join(_paths.first, "gems", "m-1"),
        spec.gem_dir,
        "Wrong spec after require for #{_name}"

      spec.instance_variable_set :@activated, false
      Gem.loaded_specs.delete(spec.name)
      $:.delete(File.join(spec.gem_dir, "lib"))
    end
  end

  def test_gem_path_ordering_short
    write_file File.join(@tempdir, 'lib', "g.rb") { |fp| fp.puts "" }
    write_file File.join(@tempdir, 'lib', 'm.rb') { |fp| fp.puts "" }

    g = util_spec 'g', '1', nil, "lib/g.rb"
    m = util_spec 'm', '1', nil, "lib/m.rb"

    install_gem g, :install_dir => Gem.dir
    install_gem m, :install_dir => Gem.dir
    install_gem m, :install_dir => Gem.user_dir

    Gem.use_paths Gem.dir, [ Gem.dir, Gem.user_dir]

    assert_equal \
      File.join(Gem.dir, "gems", "m-1"),
      Gem::Dependency.new('m','1').to_spec.gem_dir,
      "Wrong spec selected"
  end

  def test_auto_activation_of_specific_gemdeps_file
    a = util_spec "a", "1", nil, "lib/a.rb"
    b = util_spec "b", "1", nil, "lib/b.rb"
    c = util_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    ENV['RUBYGEMS_GEMDEPS'] = path

    Gem.use_gemdeps

    assert_equal add_bundler_full_name(%W(a-1 b-1 c-1)), loaded_spec_names
  end

  def test_auto_activation_of_used_gemdeps_file
    a = util_spec "a", "1", nil, "lib/a.rb"
    b = util_spec "b", "1", nil, "lib/b.rb"
    c = util_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    ENV['RUBYGEMS_GEMDEPS'] = "-"

    expected_specs = [a, b, util_spec("bundler", Bundler::VERSION), c].compact
    assert_equal expected_specs, Gem.use_gemdeps.sort_by { |s| s.name }
  end

  LIB_PATH = File.expand_path "../../../lib".dup.tap(&Gem::UNTAINT), __FILE__.dup.tap(&Gem::UNTAINT)
  BUNDLER_LIB_PATH = File.expand_path $LOAD_PATH.find {|lp| File.file?(File.join(lp, "bundler.rb")) }.dup.tap(&Gem::UNTAINT)
  BUNDLER_FULL_NAME = "bundler-#{Bundler::VERSION}".freeze

  def add_bundler_full_name(names)
    names << BUNDLER_FULL_NAME
    names.sort!
    names
  end

  def test_looks_for_gemdeps_files_automatically_on_start
    skip "Requiring bundler messes things up" if Gem.java_platform?

    a = util_spec "a", "1", nil, "lib/a.rb"
    b = util_spec "b", "1", nil, "lib/b.rb"
    c = util_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join(@tempdir, "gd-tmp")
    install_gem a, :install_dir => path
    install_gem b, :install_dir => path
    install_gem c, :install_dir => path

    ENV['GEM_PATH'] = path
    ENV['RUBYGEMS_GEMDEPS'] = "-"

    path = File.join @tempdir, "gem.deps.rb"
    cmd = [Gem.ruby.dup.tap(&Gem::UNTAINT), "-I#{LIB_PATH.tap(&Gem::UNTAINT)}",
           "-I#{BUNDLER_LIB_PATH.tap(&Gem::UNTAINT)}", "-rrubygems"]
    cmd << "-eputs Gem.loaded_specs.values.map(&:full_name).sort"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
    end
    out0 = IO.popen(cmd, &:read).split(/\n/)

    File.open path, "a" do |f|
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end
    out = IO.popen(cmd, &:read).split(/\n/)

    assert_equal ["b-1", "c-1"], out - out0
  end

  def test_looks_for_gemdeps_files_automatically_on_start_in_parent_dir
    skip "Requiring bundler messes things up" if Gem.java_platform?

    a = util_spec "a", "1", nil, "lib/a.rb"
    b = util_spec "b", "1", nil, "lib/b.rb"
    c = util_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join(@tempdir, "gd-tmp")
    install_gem a, :install_dir => path
    install_gem b, :install_dir => path
    install_gem c, :install_dir => path

    ENV['GEM_PATH'] = path
    ENV['RUBYGEMS_GEMDEPS'] = "-"

    Dir.mkdir "sub1"

    path = File.join @tempdir, "gem.deps.rb"
    cmd = [Gem.ruby.dup.tap(&Gem::UNTAINT), "-Csub1", "-I#{LIB_PATH.tap(&Gem::UNTAINT)}",
           "-I#{BUNDLER_LIB_PATH.tap(&Gem::UNTAINT)}", "-rrubygems"]
    cmd << "-eputs Gem.loaded_specs.values.map(&:full_name).sort"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
    end
    out0 = IO.popen(cmd, &:read).split(/\n/)

    File.open path, "a" do |f|
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end
    out = IO.popen(cmd, &:read).split(/\n/)

    Dir.rmdir "sub1"

    assert_equal ["b-1", "c-1"], out - out0
  end

  def test_register_default_spec
    Gem.clear_default_specs

    old_style = Gem::Specification.new do |spec|
      spec.files = ["foo.rb", "bar.rb"]
    end

    Gem.register_default_spec old_style

    assert_equal old_style, Gem.find_unresolved_default_spec("foo.rb")
    assert_equal old_style, Gem.find_unresolved_default_spec("bar.rb")
    assert_nil              Gem.find_unresolved_default_spec("baz.rb")

    Gem.clear_default_specs

    new_style = Gem::Specification.new do |spec|
      spec.files = ["lib/foo.rb", "ext/bar.rb", "bin/exec", "README"]
      spec.require_paths = ["lib", "ext"]
    end

    Gem.register_default_spec new_style

    assert_equal new_style, Gem.find_unresolved_default_spec("foo.rb")
    assert_equal new_style, Gem.find_unresolved_default_spec("bar.rb")
    assert_nil              Gem.find_unresolved_default_spec("exec")
    assert_nil              Gem.find_unresolved_default_spec("README")
  end

  def test_use_gemdeps
    gem_deps_file = 'gem.deps.rb'.tap(&Gem::UNTAINT)
    spec = util_spec 'a', 1
    install_specs spec

    spec = Gem::Specification.find { |s| s == spec }
    refute spec.activated?

    File.open gem_deps_file, 'w' do |io|
      io.write 'gem "a"'
    end

    assert_nil Gem.gemdeps

    Gem.use_gemdeps gem_deps_file

    assert_equal add_bundler_full_name(%W(a-1)), loaded_spec_names
    refute_nil Gem.gemdeps
  end

  def test_use_gemdeps_ENV
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], nil

    spec = util_spec 'a', 1

    refute spec.activated?

    File.open 'gem.deps.rb', 'w' do |io|
      io.write 'gem "a"'
    end

    Gem.use_gemdeps

    refute spec.activated?
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_argument_missing
    e = assert_raises ArgumentError do
      Gem.use_gemdeps 'gem.deps.rb'
    end

    assert_equal 'Unable to find gem dependencies file at gem.deps.rb',
                 e.message
  end

  def test_use_gemdeps_argument_missing_match_ENV
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] =
      ENV['RUBYGEMS_GEMDEPS'], 'gem.deps.rb'

    e = assert_raises ArgumentError do
      Gem.use_gemdeps 'gem.deps.rb'
    end

    assert_equal 'Unable to find gem dependencies file at gem.deps.rb',
                 e.message
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_automatic
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], '-'

    spec = util_spec 'a', 1
    install_specs spec
    spec = Gem::Specification.find { |s| s == spec }

    refute spec.activated?

    File.open 'Gemfile', 'w' do |io|
      io.write 'gem "a"'
    end

    Gem.use_gemdeps

    assert_equal add_bundler_full_name(%W(a-1)), loaded_spec_names
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_automatic_missing
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], '-'

    Gem.use_gemdeps

    assert true # count
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_disabled
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], ''

    spec = util_spec 'a', 1

    refute spec.activated?

    File.open 'gem.deps.rb', 'w' do |io|
      io.write 'gem "a"'
    end

    Gem.use_gemdeps

    refute spec.activated?
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_missing_gem
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], 'x'

    File.open 'x', 'w' do |io|
      io.write 'gem "a"'
    end

    platform = Bundler::GemHelpers.generic_local_platform
    if platform == Gem::Platform::RUBY
      platform = ''
    else
      platform = " #{platform}"
    end

    expected = <<-EXPECTED
Could not find gem 'a#{platform}' in any of the gem sources listed in your Gemfile.
You may need to `gem install -g` to install missing gems

    EXPECTED

    Gem::Deprecate.skip_during do
      assert_output nil, expected do
        Gem.use_gemdeps
      end
    end
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_use_gemdeps_specific
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], 'x'

    spec = util_spec 'a', 1
    install_specs spec

    spec = Gem::Specification.find { |s| s == spec }
    refute spec.activated?

    File.open 'x', 'w' do |io|
      io.write 'gem "a"'
    end

    Gem.use_gemdeps

    assert_equal add_bundler_full_name(%W(a-1)), loaded_spec_names
  ensure
    ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
  end

  def test_operating_system_defaults
    operating_system_defaults = Gem.operating_system_defaults

    assert operating_system_defaults != nil
    assert operating_system_defaults.is_a? Hash
  end

  def test_platform_defaults
    platform_defaults = Gem.platform_defaults

    assert platform_defaults != nil
    assert platform_defaults.is_a? Hash
  end

  def ruby_install_name(name)
    orig_RUBY_INSTALL_NAME = RbConfig::CONFIG['ruby_install_name']
    RbConfig::CONFIG['ruby_install_name'] = name

    yield
  ensure
    if orig_RUBY_INSTALL_NAME
      RbConfig::CONFIG['ruby_install_name'] = orig_RUBY_INSTALL_NAME
    else
      RbConfig::CONFIG.delete 'ruby_install_name'
    end
  end

  def with_bindir_and_exeext(bindir, exeext)
    orig_bindir = RbConfig::CONFIG['bindir']
    orig_exe_ext = RbConfig::CONFIG['EXEEXT']

    RbConfig::CONFIG['bindir'] = bindir
    RbConfig::CONFIG['EXEEXT'] = exeext

    yield
  ensure
    RbConfig::CONFIG['bindir'] = orig_bindir
    RbConfig::CONFIG['EXEEXT'] = orig_exe_ext
  end

  def with_clean_path_to_ruby
    orig_ruby = Gem.ruby

    Gem.instance_variable_set :@ruby, nil

    yield
  ensure
    Gem.instance_variable_set :@ruby, orig_ruby
  end

  def with_plugin(path)
    test_plugin_path = File.expand_path("test/rubygems/plugin/#{path}",
                                        PROJECT_DIR)

    # A single test plugin should get loaded once only, in order to preserve
    # sane test semantics.
    refute_includes $LOAD_PATH, test_plugin_path
    $LOAD_PATH.unshift test_plugin_path

    capture_io do
      yield
    end
  ensure
    $LOAD_PATH.delete test_plugin_path
  end

  def util_ensure_gem_dirs
    Gem.ensure_gem_subdirectories @gemhome

    #
    # FIXME what does this solve precisely? -ebh
    #
    @additional.each do |dir|
      Gem.ensure_gem_subdirectories @gemhome
    end
  end

  def util_exec_gem
    spec, _ = util_spec 'a', '4' do |s|
      s.executables = ['exec', 'abin']
    end

    @exec_path = File.join spec.full_gem_path, spec.bindir, 'exec'
    @abin_path = File.join spec.full_gem_path, spec.bindir, 'abin'
    spec
  end

  def util_remove_interrupt_command
    Gem::Commands.send :remove_const, :InterruptCommand if
      Gem::Commands.const_defined? :InterruptCommand
  end

  def util_cache_dir
    File.join Gem.dir, "cache"
  end

end
