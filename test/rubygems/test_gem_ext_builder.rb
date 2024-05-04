# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"
require "rubygems/installer"

class TestGemExtBuilder < Gem::TestCase
  def setup
    @orig_destdir = ENV["DESTDIR"]
    @orig_make = ENV["make"]
    super

    @ext = File.join @tempdir, "ext"
    @dest_path = File.join @tempdir, "prefix"

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path

    @spec = util_spec "a"

    @builder = Gem::Ext::Builder.new @spec, ""
  end

  def teardown
    super
    ENV["DESTDIR"] = @orig_destdir
    ENV["make"] = @orig_make
  end

  def test_class_make
    ENV["DESTDIR"] = "destination"
    results = []

    File.open File.join(@ext, "Makefile"), "w" do |io|
      io.puts <<-MAKEFILE
all:
\t@#{Gem.ruby} -e "puts %Q{all: \#{ENV['DESTDIR']}}"

clean:
\t@#{Gem.ruby} -e "puts %Q{clean: \#{ENV['DESTDIR']}}"

install:
\t@#{Gem.ruby} -e "puts %Q{install: \#{ENV['DESTDIR']}}"
      MAKEFILE
    end

    Gem::Ext::Builder.make @dest_path, results, @ext

    results = results.join("\n").b

    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]} clean$/,   results)
    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]}$/,         results)
    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]} install$/, results)

    unless results.include?("nmake")
      assert_match(/^clean: destination$/,   results)
      assert_match(/^all: destination$/,     results)
      assert_match(/^install: destination$/, results)
    end
  end

  def test_class_make_no_clean
    ENV["DESTDIR"] = "destination"
    results = []

    File.open File.join(@ext, "Makefile"), "w" do |io|
      io.puts <<-MAKEFILE
all:
\t@#{Gem.ruby} -e "puts %Q{all: \#{ENV['DESTDIR']}}"

install:
\t@#{Gem.ruby} -e "puts %Q{install: \#{ENV['DESTDIR']}}"
      MAKEFILE
    end

    Gem::Ext::Builder.make @dest_path, results, @ext

    results = results.join("\n").b

    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]} clean$/,   results)
    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]}$/,         results)
    assert_match(/DESTDIR\\=#{ENV["DESTDIR"]} install$/, results)
  end

  def test_custom_make_with_options
    pend "native windows platform only provides nmake" if vc_windows?

    ENV["make"] = "make V=1"
    results = []
    File.open File.join(@ext, "Makefile"), "w" do |io|
      io.puts <<-MAKEFILE
all:
\t@#{Gem.ruby} -e "puts 'all: OK'"

clean:
\t@#{Gem.ruby} -e "puts 'clean: OK'"

install:
\t@#{Gem.ruby} -e "puts 'install: OK'"
      MAKEFILE
    end
    Gem::Ext::Builder.make @dest_path, results, @ext
    results = results.join("\n").b
    assert_match(/clean: OK/, results)
    assert_match(/all: OK/, results)
    assert_match(/install: OK/, results)
  end

  def test_build_extensions
    pend "terminates on mswin" if vc_windows? && ruby_repo?

    extension_in_lib do
      @spec.extensions << "ext/extconf.rb"

      ext_dir = File.join @spec.gem_dir, "ext"

      FileUtils.mkdir_p ext_dir

      extconf_rb = File.join ext_dir, "extconf.rb"

      File.open extconf_rb, "w" do |f|
        f.write <<-'RUBY'
          require 'mkmf'

          create_makefile 'a'
        RUBY
      end

      ext_lib_dir = File.join ext_dir, "lib"
      FileUtils.mkdir ext_lib_dir
      FileUtils.touch File.join ext_lib_dir, "a.rb"
      FileUtils.mkdir File.join ext_lib_dir, "a"
      FileUtils.touch File.join ext_lib_dir, "a", "b.rb"

      use_ui @ui do
        @builder.build_extensions
      end

      assert_path_exist @spec.extension_dir
      assert_path_exist @spec.gem_build_complete_path
      assert_path_exist File.join @spec.extension_dir, "gem_make.out"
      assert_path_exist File.join @spec.extension_dir, "a.rb"
      assert_path_exist File.join @spec.gem_dir, "lib", "a.rb"
      assert_path_exist File.join @spec.gem_dir, "lib", "a", "b.rb"
    end
  end

  def test_build_extensions_with_gemhome_with_space
    pend "terminates on mswin" if vc_windows? && ruby_repo?
    new_gemhome = File.join @tempdir, "gem home"
    File.rename(@gemhome, new_gemhome)
    @gemhome = new_gemhome
    Gem.use_paths(@gemhome)
    @spec = util_spec "a"
    @builder = Gem::Ext::Builder.new @spec, ""

    test_build_extensions
  end

  def test_build_extensions_install_ext_only
    pend "terminates on mswin" if vc_windows? && ruby_repo?

    extension_in_lib(false) do
      @orig_install_extension_in_lib = Gem.configuration.install_extension_in_lib
      Gem.configuration.install_extension_in_lib = false

      @spec.extensions << "ext/extconf.rb"

      ext_dir = File.join @spec.gem_dir, "ext"

      FileUtils.mkdir_p ext_dir

      extconf_rb = File.join ext_dir, "extconf.rb"

      File.open extconf_rb, "w" do |f|
        f.write <<-'RUBY'
          require 'mkmf'

          create_makefile 'a'
        RUBY
      end

      ext_lib_dir = File.join ext_dir, "lib"
      FileUtils.mkdir ext_lib_dir
      FileUtils.touch File.join ext_lib_dir, "a.rb"
      FileUtils.mkdir File.join ext_lib_dir, "a"
      FileUtils.touch File.join ext_lib_dir, "a", "b.rb"

      use_ui @ui do
        @builder.build_extensions
      end

      assert_path_exist @spec.extension_dir
      assert_path_exist @spec.gem_build_complete_path
      assert_path_exist File.join @spec.extension_dir, "gem_make.out"
      assert_path_exist File.join @spec.extension_dir, "a.rb"
      assert_path_not_exist File.join @spec.gem_dir, "lib", "a.rb"
      assert_path_not_exist File.join @spec.gem_dir, "lib", "a", "b.rb"
    end
  ensure
    Gem.configuration.install_extension_in_lib = @orig_install_extension_in_lib
  end

  def test_build_extensions_none
    use_ui @ui do
      @builder.build_extensions
    end

    assert_equal "", @ui.output
    assert_equal "", @ui.error

    assert_path_not_exist File.join @spec.extension_dir, "gem_make.out"
  end

  def test_build_extensions_rebuild_failure
    FileUtils.mkdir_p @spec.extension_dir
    FileUtils.touch @spec.gem_build_complete_path

    @spec.extensions << nil

    assert_raise Gem::Ext::BuildError do
      use_ui @ui do
        @builder.build_extensions
      end
    end

    assert_path_not_exist @spec.gem_build_complete_path
  end

  def test_build_extensions_extconf_bad
    cwd = Dir.pwd

    @spec.extensions << "extconf.rb"

    FileUtils.mkdir_p @spec.gem_dir

    e = assert_raise Gem::Ext::BuildError do
      use_ui @ui do
        @builder.build_extensions
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)
    assert_equal "Building native extensions. This could take a while...\n", @ui.output
    assert_equal "", @ui.error

    gem_make_out = File.join @spec.extension_dir, "gem_make.out"
    cmd_make_out = File.read(gem_make_out)

    assert_match %r{#{Regexp.escape Gem.ruby} .* extconf\.rb}, cmd_make_out
    assert_match(/: No such file/, cmd_make_out)

    assert_path_not_exist @spec.gem_build_complete_path

    assert_equal cwd, Dir.pwd
  end

  def test_build_extensions_unsupported
    FileUtils.mkdir_p @spec.gem_dir
    gem_make_out = File.join @spec.extension_dir, "gem_make.out"
    @spec.extensions << nil

    e = assert_raise Gem::Ext::BuildError do
      use_ui @ui do
        @builder.build_extensions
      end
    end

    assert_match(/^\s*No builder for extension ''$/, e.message)
    assert_equal "Building native extensions. This could take a while...\n", @ui.output
    assert_equal "", @ui.error

    assert_equal "No builder for extension ''\n", File.read(gem_make_out)

    assert_path_not_exist @spec.gem_build_complete_path
  ensure
    FileUtils.rm_f gem_make_out
  end

  def test_build_extensions_with_build_args
    args = ["--aa", "--bb"]
    @builder.build_args = args
    @spec.extensions << "extconf.rb"

    FileUtils.mkdir_p @spec.gem_dir

    File.open File.join(@spec.gem_dir, "extconf.rb"), "w" do |f|
      f.write <<-'RUBY'
        puts "IN EXTCONF"
        extconf_args = File.join __dir__, 'extconf_args'
        File.open extconf_args, 'w' do |f|
          f.puts ARGV.inspect
        end

        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo cleaned"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    use_ui @ui do
      @builder.build_extensions
    end

    path = File.join @spec.gem_dir, "extconf_args"

    assert_equal args.inspect, File.read(path).strip
    assert_path_exist @spec.extension_dir
  end

  def test_build_extensions_with_target_rbconfig
    fake_rbconfig = File.join @tempdir, "fake_rbconfig.rb"
    File.open fake_rbconfig, "w" do |f|
      f.write <<~RUBY
      module RbConfig
        CONFIG = {}
        MAKEFILE_CONFIG = {}

        def self.fire_update!(key, value); end
        def self.expand(val, config = CONFIG); val; end
      end
      RUBY
      RbConfig::CONFIG.each do |k, v|
        f.puts %(RbConfig::CONFIG["#{k}"] = "#{v}")
      end
      RbConfig::MAKEFILE_CONFIG.each do |k, v|
        f.puts %(RbConfig::MAKEFILE_CONFIG["#{k}"] = "#{v}")
      end
      f.puts "RbConfig::CONFIG['host_os'] = 'fake_os'"
      f.puts "RbConfig::CONFIG['arch'] = 'fake_arch'"
    end

    system(Gem.ruby, "-rmkmf", "-e", "exit MakeMakefile::RbConfig::CONFIG['host_os'] == 'fake_os'",
           "--", "--target-rbconfig=#{fake_rbconfig}")
    pend "This version of mkmf does not support --target-rbconfig" unless $?.success?

    @spec.extensions << "extconf.rb"
    @builder = Gem::Ext::Builder.new @spec, "", Gem::TargetRbConfig.from_path(fake_rbconfig)

    FileUtils.mkdir_p @spec.gem_dir

    File.open File.join(@spec.gem_dir, "extconf.rb"), "w" do |f|
      f.write <<-'RUBY'
        require 'mkmf'

        extconf_args = File.join __dir__, 'rbconfig_dump'
        File.open extconf_args, 'w' do |f|
          ["host_os", "arch"].each do |k|
            f.puts "#{k}=#{MakeMakefile::RbConfig::CONFIG[k]}"
          end
        end

        create_makefile 'a'
      RUBY
    end

    use_ui @ui do
      @builder.build_extensions
    end

    path = File.join @spec.gem_dir, "rbconfig_dump"

    assert_equal <<~DUMP, File.read(path)
    host_os=fake_os
    arch=fake_arch
    DUMP
    assert_path_exist @spec.extension_dir
  end

  def test_initialize
    build_info_dir = File.join @gemhome, "build_info"

    FileUtils.mkdir_p build_info_dir

    build_info_file = File.join build_info_dir, "#{@spec.full_name}.info"

    File.open build_info_file, "w" do |io|
      io.puts "--with-foo-dir=/nonexistent"
    end

    builder = Gem::Ext::Builder.new @spec

    assert_equal %w[--with-foo-dir=/nonexistent], builder.build_args
  end

  def test_initialize_build_args
    builder = Gem::Ext::Builder.new @spec, %w[--with-foo-dir=/nonexistent]

    assert_equal %w[--with-foo-dir=/nonexistent], builder.build_args
  end
end unless Gem.java_platform?
