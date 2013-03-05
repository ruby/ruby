# coding: US-ASCII
require 'rubygems/test_case'
require 'rubygems'
require 'rubygems/installer'
require 'pathname'
require 'tmpdir'

# TODO: push this up to test_case.rb once battle tested
$SAFE=1
$LOAD_PATH.map! do |path|
  path.dup.untaint
end

class TestGem < Gem::TestCase

  def setup
    super

    ENV.delete 'RUBYGEMS_GEMDEPS'
    @additional = %w[a b].map { |d| File.join @tempdir, d }

    util_remove_interrupt_command
  end

  def assert_activate expected, *specs
    specs.each do |spec|
      case spec
      when String then
        Gem::Specification.find_by_name(spec).activate
      when Gem::Specification then
        spec.activate
      else
        flunk spec.inspect
      end
    end

    loaded = Gem.loaded_specs.values.map(&:full_name)

    assert_equal expected.sort, loaded.sort if expected
  end

  def test_self_activate
    foo = util_spec 'foo', '1'

    assert_activate %w[foo-1], foo
  end

  def loaded_spec_names
    Gem.loaded_specs.values.map(&:full_name).sort
  end

  def unresolved_names
    Gem::Specification.unresolved_deps.values.map(&:to_s).sort
  end

  # TODO: move these to specification
  def test_self_activate_via_require
    a1 = new_spec "a", "1", "b" => "= 1"
    b1 = new_spec "b", "1", nil, "lib/b/c.rb"
    b2 = new_spec "b", "2", nil, "lib/b/c.rb"

    install_specs a1, b1, b2

    a1.activate
    save_loaded_features do
      require "b/c"
    end

    assert_equal %w(a-1 b-1), loaded_spec_names
  end

  # TODO: move these to specification
  def test_self_activate_deep_unambiguous
    a1 = new_spec "a", "1", "b" => "= 1"
    b1 = new_spec "b", "1", "c" => "= 1"
    b2 = new_spec "b", "2", "c" => "= 2"
    c1 = new_spec "c", "1"
    c2 = new_spec "c", "2"

    install_specs a1, b1, b2, c1, c2

    a1.activate
    assert_equal %w(a-1 b-1 c-1), loaded_spec_names
  end

  def save_loaded_features
    old_loaded_features = $LOADED_FEATURES.dup
    yield
  ensure
    $LOADED_FEATURES.replace old_loaded_features
  end

  # TODO: move these to specification
  def test_self_activate_ambiguous_direct
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      b1 = new_spec("b", "1", { "c" => ">= 1" }, "lib/d.rb")
      b2 = new_spec("b", "2", { "c" => ">= 2" }, "lib/d.rb")
      c1 = new_spec "c", "1"
      c2 = new_spec "c", "2"

      Gem::Specification.reset
      install_specs a1, b1, b2, c1, c2

      a1.activate
      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      require "d"

      assert_equal %w(a-1 b-2 c-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  # TODO: move these to specification
  def test_self_activate_ambiguous_indirect
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      b1 = new_spec "b", "1", "c" => ">= 1"
      b2 = new_spec "b", "2", "c" => ">= 2"
      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec "c", "2", nil, "lib/d.rb"

      install_specs a1, b1, b2, c1, c2

      a1.activate
      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      require "d"

      assert_equal %w(a-1 b-2 c-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_self_finish_resolve
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      b1 = new_spec "b", "1", "c" => ">= 1"
      b2 = new_spec "b", "2", "c" => ">= 2"
      c1 = new_spec "c", "1"
      c2 = new_spec "c", "2"

      install_specs a1, b1, b2, c1, c2

      a1.activate

      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      Gem.finish_resolve

      assert_equal %w(a-1 b-2 c-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_self_activate_via_require_wtf
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0", "d" => "> 0"    # this
      b1 = new_spec "b", "1", { "c" => ">= 1" }, "lib/b.rb"
      b2 = new_spec "b", "2", { "c" => ">= 2" }, "lib/b.rb" # this
      c1 = new_spec "c", "1"
      c2 = new_spec "c", "2"                                # this
      d1 = new_spec "d", "1", { "c" => "< 2" },  "lib/d.rb"
      d2 = new_spec "d", "2", { "c" => "< 2" },  "lib/d.rb" # this

      install_specs a1, b1, b2, c1, c2, d1, d2

      a1.activate

      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)", "d (> 0)"], unresolved_names

      require "b"

      e = assert_raises Gem::LoadError do
        require "d"
      end

      assert_equal "unable to find a version of 'd' to activate", e.message

      assert_equal %w(a-1 b-2 c-2), loaded_spec_names
      assert_equal ["d (> 0)"], unresolved_names
    end
  end

  def test_self_finish_resolve_wtf
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0", "d" => "> 0"    # this
      b1 = new_spec "b", "1", { "c" => ">= 1" }, "lib/b.rb" # this
      b2 = new_spec "b", "2", { "c" => ">= 2" }, "lib/b.rb"
      c1 = new_spec "c", "1"                                # this
      c2 = new_spec "c", "2"
      d1 = new_spec "d", "1", { "c" => "< 2" },  "lib/d.rb"
      d2 = new_spec "d", "2", { "c" => "< 2" },  "lib/d.rb" # this

      install_specs a1, b1, b2, c1, c2, d1, d2

      a1.activate

      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)", "d (> 0)"], unresolved_names

      Gem.finish_resolve

      assert_equal %w(a-1 b-1 c-1 d-2), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  # TODO: move these to specification
  def test_self_activate_ambiguous_unrelated
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      b1 = new_spec "b", "1", "c" => ">= 1"
      b2 = new_spec "b", "2", "c" => ">= 2"
      c1 = new_spec "c", "1"
      c2 = new_spec "c", "2"
      d1 = new_spec "d", "1", nil, "lib/d.rb"

      install_specs a1, b1, b2, c1, c2, d1

      a1.activate
      assert_equal %w(a-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      require "d"

      assert_equal %w(a-1 d-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names
    end
  end

  # TODO: move these to specification
  def test_self_activate_ambiguous_indirect_conflict
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      a2 = new_spec "a", "2", "b" => "> 0"
      b1 = new_spec "b", "1", "c" => ">= 1"
      b2 = new_spec "b", "2", "c" => ">= 2"
      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec("c", "2", { "a" => "1" }, "lib/d.rb") # conflicts with a-2

      install_specs a1, a2, b1, b2, c1, c2

      a2.activate
      assert_equal %w(a-2), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      require "d"

      assert_equal %w(a-2 b-1 c-1), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  # TODO: move these to specification
  def test_require_already_activated
    save_loaded_features do
      a1 = new_spec "a", "1", nil, "lib/d.rb"

      install_specs a1 # , a2, b1, b2, c1, c2

      a1.activate
      assert_equal %w(a-1), loaded_spec_names
      assert_equal [], unresolved_names

      assert require "d"

      assert_equal %w(a-1), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  # TODO: move these to specification
  def test_require_already_activated_indirect_conflict
    save_loaded_features do
      a1 = new_spec "a", "1", "b" => "> 0"
      a2 = new_spec "a", "2", "b" => "> 0"
      b1 = new_spec "b", "1", "c" => ">= 1"
      b2 = new_spec "b", "2", "c" => ">= 2"
      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec("c", "2", { "a" => "1" }, "lib/d.rb") # conflicts with a-2

      install_specs a1, a2, b1, b2, c1, c2

      a1.activate
      c1.activate
      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      assert require "d"

      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names
    end
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
      a1 = new_spec "a", "1", nil, "lib/a1.rb"

      install_specs a1

      assert_raises ::LoadError do
        require "a*"
      end

      assert_equal [], loaded_spec_names
    end
  end

  # TODO: move these to specification
  def test_self_activate_loaded
    foo = util_spec 'foo', '1'

    assert foo.activate
    refute foo.activate
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 2.0)
  # [C] depends on nothing

  def test_self_activate_unrelated
    a = util_spec 'a', '1.0', 'b' => '>= 1.0'
        util_spec 'b', '1.0'
    c = util_spec 'c', '1.0'

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 2.0)
  #     [C]  = 1.0 depends on
  #         [B] ~> 1.0
  #
  # and should resolve using b-1.0
  # TODO: move these to specification

  def test_self_activate_over
    a = util_spec 'a', '1.0', 'b' => '>= 1.0', 'c' => '= 1.0'
    util_spec 'b', '1.0'
    util_spec 'b', '1.1'
    util_spec 'b', '2.0'
    util_spec 'c', '1.0', 'b' => '~> 1.0'

    a.activate

    assert_equal %w[a-1.0 c-1.0], loaded_spec_names
    assert_equal ["b (>= 1.0, ~> 1.0)"], unresolved_names
  end

  ##
  # [A] depends on
  #     [B] ~> 1.0 (satisfied by 1.1)
  #     [C]  = 1.0 depends on
  #         [B] = 1.0
  #
  # and should resolve using b-1.0
  #
  # TODO: this is not under, but over... under would require depth
  # first resolve through a dependency that is later pruned.

  def test_self_activate_under
    a,   _ = util_spec 'a', '1.0', 'b' => '~> 1.0', 'c' => '= 1.0'
             util_spec 'b', '1.0'
             util_spec 'b', '1.1'
    c,   _ = util_spec 'c', '1.0', 'b' => '= 1.0'

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  ##
  # [A1] depends on
  #    [B] > 0 (satisfied by 2.0)
  # [B1] depends on
  #    [C] > 0 (satisfied by 1.0)
  # [B2] depends on nothing!
  # [C1] depends on nothing

  def test_self_activate_dropped
    a1, = util_spec 'a', '1', 'b' => nil
          util_spec 'b', '1', 'c' => nil
          util_spec 'b', '2'
          util_spec 'c', '1'

    assert_activate %w[b-2 a-1], a1, "b"
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 1.1) depends on
  #         [Z]
  #     [C] >= 1.0 depends on
  #         [B] = 1.0
  #
  # and should backtrack to resolve using b-1.0, pruning Z from the
  # resolve.

  def test_self_activate_raggi_the_edgecase_generator
    a,  _ = util_spec 'a', '1.0', 'b' => '>= 1.0', 'c' => '>= 1.0'
            util_spec 'b', '1.0'
            util_spec 'b', '1.1', 'z' => '>= 1.0'
    c,  _ = util_spec 'c', '1.0', 'b' => '= 1.0'

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  def test_self_activate_conflict
    util_spec 'b', '1.0'
    util_spec 'b', '2.0'

    gem "b", "= 1.0"

    assert_raises Gem::LoadError do
      gem "b", "= 2.0"
    end
  end

  ##
  # [A] depends on
  #     [C]  = 1.0 depends on
  #         [B] = 2.0
  #     [B] ~> 1.0 (satisfied by 1.0)

  def test_self_activate_checks_dependencies
    a, _  = util_spec 'a', '1.0'
            a.add_dependency 'c', '= 1.0'
            a.add_dependency 'b', '~> 1.0'

            util_spec 'b', '1.0'
            util_spec 'b', '2.0'
    c,  _ = util_spec 'c', '1.0', 'b' => '= 2.0'

    e = assert_raises Gem::LoadError do
      assert_activate nil, a, c, "b"
    end

    expected = "can't satisfy 'b (~> 1.0)', already activated 'b-2.0'"
    assert_equal expected, e.message
  end

  ##
  # [A] depends on
  #     [B] ~> 1.0 (satisfied by 1.0)
  #     [C]  = 1.0 depends on
  #         [B] = 2.0

  def test_self_activate_divergent
    a, _  = util_spec 'a', '1.0', 'b' => '~> 1.0', 'c' => '= 1.0'
            util_spec 'b', '1.0'
            util_spec 'b', '2.0'
    c,  _ = util_spec 'c', '1.0', 'b' => '= 2.0'

    e = assert_raises Gem::LoadError do
      assert_activate nil, a, c, "b"
    end

    assert_match(/Unable to activate c-1.0,/, e.message)
    assert_match(/because b-1.0 conflicts with b .= 2.0/, e.message)
  end

  ##
  # DOC

  def test_self_activate_platform_alternate
    @x1_m = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @x1_o = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    @w1 = util_spec 'w', '1', 'x' => nil

    util_set_arch 'cpu-my_platform1'

    assert_activate %w[x-1-cpu-my_platform-1 w-1], @w1, @x1_m
  end

  ##
  # DOC

  def test_self_activate_platform_bump
    @y1 = util_spec 'y', '1'

    @y1_1_p = util_spec 'y', '1.1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @z1 = util_spec 'z', '1', 'y' => nil

    assert_activate %w[y-1 z-1], @z1, @y1
  end

  ##
  # [C] depends on
  #     [A] = 1.a
  #     [B] = 1.0 depends on
  #         [A] >= 0 (satisfied by 1.a)

  def test_self_activate_prerelease
    @c1_pre = util_spec 'c', '1.a', "a" => "1.a", "b" => "1"
    @a1_pre = util_spec 'a', '1.a'
    @b1     = util_spec 'b', '1' do |s|
      s.add_dependency 'a'
      s.add_development_dependency 'aa'
    end

    assert_activate %w[a-1.a b-1 c-1.a], @c1_pre, @a1_pre, @b1
  end

  ##
  # DOC

  def test_self_activate_old_required
    e1, = util_spec 'e', '1', 'd' => '= 1'
    @d1 = util_spec 'd', '1'
    @d2 = util_spec 'd', '2'

    assert_activate %w[d-1 e-1], e1, "d"
  end

  def test_self_bin_path_no_exec_name
    e = assert_raises ArgumentError do
      Gem.bin_path 'a'
    end

    assert_equal 'you must supply exec_name', e.message
  end

  def test_self_bin_path_bin_name
    util_exec_gem
    assert_equal @abin_path, Gem.bin_path('a', 'abin')
  end

  def test_self_bin_path_bin_name_version
    util_exec_gem
    assert_equal @abin_path, Gem.bin_path('a', 'abin', '4')
  end

  def test_self_bin_path_nonexistent_binfile
    quick_spec 'a', '2' do |s|
      s.executables = ['exec']
    end
    assert_raises(Gem::GemNotFoundException) do
      Gem.bin_path('a', 'other', '2')
    end
  end

  def test_self_bin_path_no_bin_file
    quick_spec 'a', '1'
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
    util_exec_gem
    quick_spec 'a', '10' do |s|
      s.executables = []
    end
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

      foo = quick_spec 'foo' do |s| s.files = %w[data/foo.txt] end
      install_gem foo
    end

    gem 'foo'

    expected = File.join @gemhome, 'gems', foo.full_name, 'data', 'foo'

    assert_equal expected, Gem.datadir('foo')
  end

  def test_self_datadir_nonexistent_package
    assert_nil Gem.datadir('xyzzy')
  end

  def test_self_default_exec_format
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:ruby_install_name]
    Gem::ConfigMap[:ruby_install_name] = 'ruby'

    assert_equal '%s', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:ruby_install_name] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_exec_format_18
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:ruby_install_name]
    Gem::ConfigMap[:ruby_install_name] = 'ruby18'

    assert_equal '%s18', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:ruby_install_name] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_exec_format_jruby
    orig_RUBY_INSTALL_NAME = Gem::ConfigMap[:ruby_install_name]
    Gem::ConfigMap[:ruby_install_name] = 'jruby'

    assert_equal 'j%s', Gem.default_exec_format
  ensure
    Gem::ConfigMap[:ruby_install_name] = orig_RUBY_INSTALL_NAME
  end

  def test_self_default_sources
    assert_equal %w[https://rubygems.org/], Gem.default_sources
  end

  def test_self_detect_gemdeps
    rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], '-'

    FileUtils.mkdir_p 'detect/a/b'
    FileUtils.mkdir_p 'detect/a/Isolate'

    FileUtils.touch 'detect/Isolate'

    begin
      Dir.chdir 'detect/a/b'

      assert_empty Gem.detect_gemdeps
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

    assert File.directory? File.join(@gemhome, "cache")
  end

  def test_self_ensure_gem_directories_permissions
    FileUtils.rm_r @gemhome
    Gem.use_paths @gemhome

    Gem.ensure_gem_subdirectories @gemhome, 0750

    assert File.directory? File.join(@gemhome, "cache")

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

    assert File.directory?(util_cache_dir)
  end

  unless win_platform? then # only for FS that support write protection
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

  def test_self_find_files
    cwd = File.expand_path("test/rubygems", @@project_dir)
    $LOAD_PATH.unshift cwd

    discover_path = File.join 'lib', 'sff', 'discover.rb'

    foo1, foo2 = %w(1 2).map { |version|
      spec = quick_gem 'sff', version do |s|
        s.files << discover_path
      end

      write_file(File.join 'gems', spec.full_name, discover_path) do |fp|
        fp.puts "# #{spec.full_name}"
      end

      spec
    }

    # HACK should be Gem.refresh
    Gem.searcher = nil
    Gem::Specification.reset

    expected = [
      File.expand_path('test/rubygems/sff/discover.rb', @@project_dir),
      File.join(foo2.full_gem_path, discover_path),
      File.join(foo1.full_gem_path, discover_path),
    ]

    assert_equal expected, Gem.find_files('sff/discover')
    assert_equal expected, Gem.find_files('sff/**.rb'), '[ruby-core:31730]'
  ensure
    assert_equal cwd, $LOAD_PATH.shift
  end

  def test_self_latest_spec_for
    a1  = quick_spec 'a', 1
    a2  = quick_spec 'a', 2
    a3a = quick_spec 'a', '3.a'

    util_setup_fake_fetcher
    util_setup_spec_fetcher a1, a2, a3a

    spec = Gem.latest_spec_for 'a'

    assert_equal a2, spec
  end

  def test_self_latest_rubygems_version
    r1 = quick_spec 'rubygems-update', '1.8.23'
    r2 = quick_spec 'rubygems-update', '1.8.24'
    r3 = quick_spec 'rubygems-update', '2.0.0.preview3'

    util_setup_fake_fetcher
    util_setup_spec_fetcher r1, r2, r3

    version = Gem.latest_rubygems_version

    assert_equal Gem::Version.new('1.8.24'), version
  end

  def test_self_latest_version_for
    a1  = quick_spec 'a', 1
    a2  = quick_spec 'a', 2
    a3a = quick_spec 'a', '3.a'

    util_setup_fake_fetcher
    util_setup_spec_fetcher a1, a2, a3a

    version = Gem.latest_version_for 'a'

    assert_equal Gem::Version.new(2), version
  end

  def test_self_loaded_specs
    foo = quick_spec 'foo'
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
    assert_equal @@project_dir, Gem.prefix
  end

  def test_self_prefix_libdir
    orig_libdir = Gem::ConfigMap[:libdir]
    Gem::ConfigMap[:libdir] = @@project_dir

    assert_nil Gem.prefix
  ensure
    Gem::ConfigMap[:libdir] = orig_libdir
  end

  def test_self_prefix_sitelibdir
    orig_sitelibdir = Gem::ConfigMap[:sitelibdir]
    Gem::ConfigMap[:sitelibdir] = @@project_dir

    assert_nil Gem.prefix
  ensure
    Gem::ConfigMap[:sitelibdir] = orig_sitelibdir
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

  def test_self_ruby_version_1_8_5
    util_set_RUBY_VERSION '1.8.5'

    assert_equal Gem::Version.new('1.8.5'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_1_8_6p287
    util_set_RUBY_VERSION '1.8.6', 287

    assert_equal Gem::Version.new('1.8.6.287'), Gem.ruby_version
  ensure
    util_restore_RUBY_VERSION
  end

  def test_self_ruby_version_1_9_2dev_r23493
    util_set_RUBY_VERSION '1.9.2', -1, 23493

    assert_equal Gem::Version.new('1.9.2.dev.23493'), Gem.ruby_version
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

    Gem.post_build do |installer| end

    assert_equal 2, Gem.post_build_hooks.length
  end

  def test_self_post_install
    assert_equal 1, Gem.post_install_hooks.length

    Gem.post_install do |installer| end

    assert_equal 2, Gem.post_install_hooks.length
  end

  def test_self_done_installing
    assert_empty Gem.done_installing_hooks

    Gem.done_installing do |gems| end

    assert_equal 1, Gem.done_installing_hooks.length
  end

  def test_self_post_reset
    assert_empty Gem.post_reset_hooks

    Gem.post_reset { }

    assert_equal 1, Gem.post_reset_hooks.length
  end

  def test_self_post_uninstall
    assert_equal 1, Gem.post_uninstall_hooks.length

    Gem.post_uninstall do |installer| end

    assert_equal 2, Gem.post_uninstall_hooks.length
  end

  def test_self_pre_install
    assert_equal 1, Gem.pre_install_hooks.length

    Gem.pre_install do |installer| end

    assert_equal 2, Gem.pre_install_hooks.length
  end

  def test_self_pre_reset
    assert_empty Gem.pre_reset_hooks

    Gem.pre_reset { }

    assert_equal 1, Gem.pre_reset_hooks.length
  end

  def test_self_pre_uninstall
    assert_equal 1, Gem.pre_uninstall_hooks.length

    Gem.pre_uninstall do |installer| end

    assert_equal 2, Gem.pre_uninstall_hooks.length
  end

  def test_self_sources
    assert_equal %w[http://gems.example.com/], Gem.sources
  end

  def test_self_try_activate_missing_dep
    a = util_spec 'a', '1.0', 'b' => '>= 1.0'

    a_file = File.join a.gem_dir, 'lib', 'a_file.rb'

    write_file a_file do |io|
      io.puts '# a_file.rb'
    end

    e = assert_raises Gem::LoadError do
      Gem.try_activate 'a_file'
    end

    assert_match %r%Could not find 'b' %, e.message
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

  def test_self_needs
    util_clear_gems
    a = util_spec "a", "1"
    b = util_spec "b", "1", "c" => nil
    c = util_spec "c", "2"

    install_specs a, b, c

    Gem.needs do |r|
      r.gem "a"
      r.gem "b", "= 1"
    end

    activated = Gem::Specification.map { |x| x.full_name }

    assert_equal %w!a-1 b-1 c-2!, activated.sort
  end

  def test_self_needs_picks_up_unresolved_deps
    save_loaded_features do
      util_clear_gems
      a = util_spec "a", "1"
      b = util_spec "b", "1", "c" => nil
      c = util_spec "c", "2"
      d =  new_spec "d", "1", {'e' => '= 1'}, "lib/d.rb"
      e = util_spec "e", "1"

      install_specs a, b, c, d, e

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

    output = Gem.gunzip input

    assert_equal 'hello', output

    return unless Object.const_defined? :Encoding

    assert_equal Encoding::BINARY, output.encoding
  end

  def test_self_gzip
    input = 'hello'

    output = Gem.gzip input

    zipped = StringIO.new output

    assert_equal 'hello', Zlib::GzipReader.new(zipped).read

    return unless Object.const_defined? :Encoding

    assert_equal Encoding::BINARY, output.encoding
  end

  if Gem.win_platform? && '1.9' > RUBY_VERSION
    # Ruby 1.9 properly handles ~ path expansion, so no need to run such tests.
    def test_self_user_home_userprofile

      Gem.clear_paths

      # safe-keep env variables
      orig_home, orig_user_profile = ENV['HOME'], ENV['USERPROFILE']

      # prepare for the test
      ENV.delete('HOME')
      ENV['USERPROFILE'] = "W:\\Users\\RubyUser"

      assert_equal 'W:/Users/RubyUser', Gem.user_home

    ensure
      ENV['HOME'] = orig_home
      ENV['USERPROFILE'] = orig_user_profile
    end

    def test_self_user_home_user_drive_and_path
      Gem.clear_paths

      # safe-keep env variables
      orig_home, orig_user_profile = ENV['HOME'], ENV['USERPROFILE']
      orig_home_drive, orig_home_path = ENV['HOMEDRIVE'], ENV['HOMEPATH']

      # prepare the environment
      ENV.delete('HOME')
      ENV.delete('USERPROFILE')
      ENV['HOMEDRIVE'] = 'Z:'
      ENV['HOMEPATH'] = "\\Users\\RubyUser"

      assert_equal 'Z:/Users/RubyUser', Gem.user_home

    ensure
      ENV['HOME'] = orig_home
      ENV['USERPROFILE'] = orig_user_profile
      ENV['HOMEDRIVE'] = orig_home_drive
      ENV['HOMEPATH'] = orig_home_path
    end
  end

  def test_load_plugins
    plugin_path = File.join "lib", "rubygems_plugin.rb"

    Dir.chdir @tempdir do
      FileUtils.mkdir_p 'lib'
      File.open plugin_path, "w" do |fp|
        fp.puts "class TestGem; TEST_SPEC_PLUGIN_LOAD = :loaded; end"
      end

      foo = quick_spec 'foo', '1' do |s|
        s.files << plugin_path
      end

      install_gem foo
    end

    Gem.searcher = nil
    Gem::Specification.reset

    gem 'foo'

    Gem.load_plugins

    assert_equal :loaded, TEST_SPEC_PLUGIN_LOAD
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

    g = new_spec 'g', '1', nil, "lib/g.rb"
    m = new_spec 'm', '1', nil, "lib/m.rb"

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
      Gem.paths = { 'GEM_HOME' => _paths.first, 'GEM_PATH' => _paths }
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

    g = new_spec 'g', '1', nil, "lib/g.rb"
    m = new_spec 'm', '1', nil, "lib/m.rb"

    install_gem g, :install_dir => Gem.dir
    install_gem m, :install_dir => Gem.dir
    install_gem m, :install_dir => Gem.user_dir

    Gem.paths = {
      'GEM_HOME' => Gem.dir,
      'GEM_PATH' => [ Gem.dir, Gem.user_dir]
    }

    assert_equal \
      File.join(Gem.dir, "gems", "m-1"),
      Gem::Dependency.new('m','1').to_spec.gem_dir,
      "Wrong spec selected"
  end

  def test_auto_activation_of_specific_gemdeps_file
    util_clear_gems

    a = new_spec "a", "1", nil, "lib/a.rb"
    b = new_spec "b", "1", nil, "lib/b.rb"
    c = new_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    ENV['RUBYGEMS_GEMDEPS'] = path

    Gem.detect_gemdeps

    assert_equal %w!a-1 b-1 c-1!, loaded_spec_names
  end

  def test_auto_activation_of_detected_gemdeps_file
    util_clear_gems

    a = new_spec "a", "1", nil, "lib/a.rb"
    b = new_spec "b", "1", nil, "lib/b.rb"
    c = new_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    ENV['RUBYGEMS_GEMDEPS'] = "-"

    assert_equal [a,b,c], Gem.detect_gemdeps
  end

  LIB_PATH = File.expand_path "../../../lib".untaint, __FILE__.untaint

  def test_looks_for_gemdeps_files_automatically_on_start
    util_clear_gems

    a = new_spec "a", "1", nil, "lib/a.rb"
    b = new_spec "b", "1", nil, "lib/b.rb"
    c = new_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    path = File.join(@tempdir, "gd-tmp")
    install_gem a, :install_dir => path
    install_gem b, :install_dir => path
    install_gem c, :install_dir => path

    ENV['GEM_PATH'] = path
    ENV['RUBYGEMS_GEMDEPS'] = "-"

    out = `#{Gem.ruby.dup.untaint} -I #{LIB_PATH.untaint} -rubygems -e "p Gem.loaded_specs.values.map(&:full_name).sort"`

    assert_equal '["a-1", "b-1", "c-1"]', out.strip
  end

  def test_looks_for_gemdeps_files_automatically_on_start_in_parent_dir
    util_clear_gems

    a = new_spec "a", "1", nil, "lib/a.rb"
    b = new_spec "b", "1", nil, "lib/b.rb"
    c = new_spec "c", "1", nil, "lib/c.rb"

    install_specs a, b, c

    path = File.join @tempdir, "gem.deps.rb"

    File.open path, "w" do |f|
      f.puts "gem 'a'"
      f.puts "gem 'b'"
      f.puts "gem 'c'"
    end

    path = File.join(@tempdir, "gd-tmp")
    install_gem a, :install_dir => path
    install_gem b, :install_dir => path
    install_gem c, :install_dir => path

    ENV['GEM_PATH'] = path
    ENV['RUBYGEMS_GEMDEPS'] = "-"

    Dir.mkdir "sub1"
    out = Dir.chdir "sub1" do
      `#{Gem.ruby.dup.untaint} -I #{LIB_PATH.untaint} -rubygems -e "p Gem.loaded_specs.values.map(&:full_name).sort"`
    end

    Dir.rmdir "sub1"

    assert_equal '["a-1", "b-1", "c-1"]', out.strip
  end

  def with_plugin(path)
    test_plugin_path = File.expand_path("test/rubygems/plugin/#{path}",
                                        @@project_dir)

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
    spec, _ = quick_spec 'a', '4' do |s|
      s.executables = ['exec', 'abin']
    end

    @exec_path = File.join spec.full_gem_path, spec.bindir, 'exec'
    @abin_path = File.join spec.full_gem_path, spec.bindir, 'abin'
  end

  def util_set_RUBY_VERSION(version, patchlevel = nil, revision = nil)
    if Gem.instance_variables.include? :@ruby_version or
       Gem.instance_variables.include? '@ruby_version' then
      Gem.send :remove_instance_variable, :@ruby_version
    end

    @RUBY_VERSION    = RUBY_VERSION
    @RUBY_PATCHLEVEL = RUBY_PATCHLEVEL if defined?(RUBY_PATCHLEVEL)
    @RUBY_REVISION   = RUBY_REVISION   if defined?(RUBY_REVISION)

    Object.send :remove_const, :RUBY_VERSION
    Object.send :remove_const, :RUBY_PATCHLEVEL if defined?(RUBY_PATCHLEVEL)
    Object.send :remove_const, :RUBY_REVISION   if defined?(RUBY_REVISION)

    Object.const_set :RUBY_VERSION,    version
    Object.const_set :RUBY_PATCHLEVEL, patchlevel if patchlevel
    Object.const_set :RUBY_REVISION,   revision   if revision
  end

  def util_restore_RUBY_VERSION
    Object.send :remove_const, :RUBY_VERSION
    Object.send :remove_const, :RUBY_PATCHLEVEL if defined?(RUBY_PATCHLEVEL)
    Object.send :remove_const, :RUBY_REVISION   if defined?(RUBY_REVISION)

    Object.const_set :RUBY_VERSION,    @RUBY_VERSION
    Object.const_set :RUBY_PATCHLEVEL, @RUBY_PATCHLEVEL if
      defined?(@RUBY_PATCHLEVEL)
    Object.const_set :RUBY_REVISION,   @RUBY_REVISION   if
      defined?(@RUBY_REVISION)
  end

  def util_remove_interrupt_command
    Gem::Commands.send :remove_const, :InterruptCommand if
      Gem::Commands.const_defined? :InterruptCommand
  end

  def util_cache_dir
    File.join Gem.dir, "cache"
  end
end

