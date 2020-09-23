# frozen_string_literal: true

require 'rubygems/test_case'
require 'rubygems/commands/setup_command'

class TestGemCommandsSetupCommand < Gem::TestCase

  bundler_gemspec = File.expand_path("../../../bundler/lib/bundler/version.rb", __FILE__)
  if File.exist?(bundler_gemspec)
    BUNDLER_VERS = File.read(bundler_gemspec).match(/VERSION = "(#{Gem::Version::VERSION_PATTERN})"/)[1]
  else
    BUNDLER_VERS = "2.0.1".freeze
  end

  def setup
    super

    @install_dir = File.join @tempdir, 'install'
    @cmd = Gem::Commands::SetupCommand.new
    @cmd.options[:prefix] = @install_dir

    filelist = %w[
      bin/gem
      lib/rubygems.rb
      lib/rubygems/test_case.rb
      lib/rubygems/ssl_certs/rubygems.org/foo.pem
      bundler/exe/bundle
      bundler/lib/bundler.rb
      bundler/lib/bundler/b.rb
      bundler/lib/bundler/templates/.circleci/config.yml
      bundler/lib/bundler/templates/.travis.yml
      bundler/man/bundle-b.1
      bundler/man/bundle-b.1.txt
      bundler/man/gemfile.5
      bundler/man/gemfile.5.txt
    ]

    create_dummy_files(filelist)

    gemspec = Gem::Specification.new
    gemspec.author = "Us"
    gemspec.name = "bundler"
    gemspec.version = BUNDLER_VERS
    gemspec.bindir = "exe"
    gemspec.executables = ["bundle"]

    File.open 'bundler/bundler.gemspec', 'w' do |io|
      io.puts gemspec.to_ruby
    end

    open(File.join(Gem.default_specifications_dir, "bundler-1.15.4.gemspec"), 'w') do |io|
      gemspec.version = "1.15.4"
      io.puts gemspec.to_ruby
    end

    spec_fetcher do |fetcher|
      fetcher.download "bundler", "1.15.4"

      fetcher.gem "bundler", BUNDLER_VERS

      fetcher.gem "bundler-audit", "1.0.0"
    end
  end

  def test_execute_regenerate_binstubs
    gem_bin_path = gem_install 'a'
    write_file gem_bin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.execute

    assert_match %r{\A#!}, File.read(gem_bin_path)
  end

  def test_execute_no_regenerate_binstubs
    gem_bin_path = gem_install 'a'
    write_file gem_bin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.options[:regenerate_binstubs] = false
    @cmd.execute

    assert_equal "I changed it!\n", File.read(gem_bin_path)
  end

  def test_execute_regenerate_plugins
    gem_plugin_path = gem_install_with_plugin 'a'
    write_file gem_plugin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.execute

    assert_match %r{\Arequire}, File.read(gem_plugin_path)
  end

  def test_execute_no_regenerate_plugins
    gem_plugin_path = gem_install_with_plugin 'a'
    write_file gem_plugin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.options[:regenerate_plugins] = false
    @cmd.execute

    assert_equal "I changed it!\n", File.read(gem_plugin_path)
  end

  def test_execute_regenerate_plugins_creates_plugins_dir_if_not_there
    gem_plugin_path = gem_install_with_plugin 'a'

    # Simulate gem installed with an older rubygems without a plugins layout
    FileUtils.rm_rf Gem.plugindir

    @cmd.options[:document] = []
    @cmd.execute

    assert_match %r{\Arequire}, File.read(gem_plugin_path)
  end

  def test_execute_informs_about_installed_executables
    @cmd.options[:document] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"

    exec_line = out.shift until exec_line == "RubyGems installed the following executables:"
    assert_equal "\t#{default_gem_bin_path}", out.shift
    assert_equal "\t#{default_bundle_bin_path}", out.shift
  end

  def test_env_shebang_flag
    gem_bin_path = gem_install 'a'
    write_file gem_bin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.options[:env_shebang] = true
    @cmd.execute

    ruby_exec = sprintf Gem.default_exec_format, 'ruby'

    bin_env = win_platform? ? "" : %w[/usr/bin/env /bin/env].find {|f| File.executable?(f) } + " "
    assert_match %r{\A#!\s*#{bin_env}#{ruby_exec}}, File.read(default_gem_bin_path)
    assert_match %r{\A#!\s*#{bin_env}#{ruby_exec}}, File.read(default_bundle_bin_path)
    assert_match %r{\A#!\s*#{bin_env}#{ruby_exec}}, File.read(gem_bin_path)
  end

  def test_pem_files_in
    assert_equal %w[rubygems/ssl_certs/rubygems.org/foo.pem],
                 @cmd.pem_files_in('lib').sort
  end

  def test_rb_files_in
    assert_equal %w[rubygems.rb rubygems/test_case.rb],
                 @cmd.rb_files_in('lib').sort
  end

  def test_bundler_man1_files_in
    assert_equal %w[bundle-b.1 bundle-b.1.txt],
                 @cmd.bundler_man1_files_in('bundler/man').sort
  end

  def test_bundler_man5_files_in
    assert_equal %w[gemfile.5 gemfile.5.txt],
                 @cmd.bundler_man5_files_in('bundler/man').sort
  end

  def test_install_lib
    @cmd.extend FileUtils

    Dir.mktmpdir 'lib' do |dir|
      @cmd.install_lib dir

      assert_path_exists File.join(dir, 'rubygems.rb')
      assert_path_exists File.join(dir, 'rubygems/ssl_certs/rubygems.org/foo.pem')

      assert_path_exists File.join(dir, 'bundler.rb')
      assert_path_exists File.join(dir, 'bundler/b.rb')

      assert_path_exists File.join(dir, 'bundler/templates/.circleci/config.yml')
      assert_path_exists File.join(dir, 'bundler/templates/.travis.yml')
    end
  end

  def test_install_man
    @cmd.extend FileUtils

    Dir.mktmpdir 'man' do |dir|
      @cmd.install_man dir

      assert_path_exists File.join("#{dir}/man1", 'bundle-b.1')
      assert_path_exists File.join("#{dir}/man1", 'bundle-b.1.txt')
      assert_path_exists File.join("#{dir}/man5", 'gemfile.5')
      assert_path_exists File.join("#{dir}/man5", 'gemfile.5.txt')
    end
  end

  def test_install_default_bundler_gem
    @cmd.extend FileUtils

    bin_dir = File.join(@gemhome, 'bin')
    @cmd.install_default_bundler_gem bin_dir

    bundler_spec = Gem::Specification.load("bundler/bundler.gemspec")
    default_spec_path = File.join(Gem.default_specifications_dir, "#{bundler_spec.full_name}.gemspec")
    spec = Gem::Specification.load(default_spec_path)

    spec.executables.each do |e|
      if Gem.win_platform?
        assert_path_exists File.join(bin_dir, "#{e}.bat")
      end

      assert_path_exists File.join bin_dir, e
    end

    default_dir = Gem.default_specifications_dir

    # expect to remove other versions of bundler gemspecs on default specification directory.
    refute_path_exists File.join(default_dir, "bundler-1.15.4.gemspec")
    assert_path_exists File.join(default_dir, "bundler-#{BUNDLER_VERS}.gemspec")

    # expect to not remove bundler-* gemspecs.
    assert_path_exists File.join(Gem.dir, "specifications", "bundler-audit-1.0.0.gemspec")

    # expect to remove normal gem that was same version. because it's promoted default gems.
    refute_path_exists File.join(Gem.dir, "specifications", "bundler-#{BUNDLER_VERS}.gemspec")

    assert_path_exists "#{Gem.dir}/gems/bundler-#{BUNDLER_VERS}"
    assert_path_exists "#{Gem.dir}/gems/bundler-1.15.4"
    assert_path_exists "#{Gem.dir}/gems/bundler-audit-1.0.0"
  end

  def test_install_default_bundler_gem_with_force_flag
    @cmd.extend FileUtils

    bin_dir = File.join(@gemhome, 'bin')
    bundle_bin = File.join(bin_dir, 'bundle')

    write_file bundle_bin do |f|
      f.puts '#!/usr/bin/ruby'
      f.puts ''
      f.puts 'echo "hello"'
    end

    bindir(bin_dir) do
      @cmd.options[:force] = true

      @cmd.install_default_bundler_gem bin_dir

      bundler_spec = Gem::Specification.load("bundler/bundler.gemspec")
      default_spec_path = File.join(Gem.default_specifications_dir, "#{bundler_spec.full_name}.gemspec")
      spec = Gem::Specification.load(default_spec_path)

      spec.executables.each do |e|
        if Gem.win_platform?
          assert_path_exists File.join(bin_dir, "#{e}.bat")
        end

        assert_path_exists File.join bin_dir, e
      end
    end
  end

  def test_remove_old_lib_files
    lib                   = File.join @install_dir, 'lib'
    lib_rubygems          = File.join lib, 'rubygems'
    lib_bundler           = File.join lib, 'bundler'
    lib_rubygems_defaults = File.join lib_rubygems, 'defaults'
    lib_bundler_templates = File.join lib_bundler, 'templates'

    securerandom_rb = File.join lib, 'securerandom.rb'

    engine_defaults_rb = File.join lib_rubygems_defaults, 'jruby.rb'
    os_defaults_rb     = File.join lib_rubygems_defaults, 'operating_system.rb'

    old_gauntlet_rubygems_rb = File.join lib, 'gauntlet_rubygems.rb'

    old_builder_rb     = File.join lib_rubygems, 'builder.rb'
    old_format_rb      = File.join lib_rubygems, 'format.rb'
    old_bundler_c_rb   = File.join lib_bundler,  'c.rb'
    old_bundler_ci     = File.join lib_bundler_templates, '.lecacy_ci', 'config.yml'

    files_that_go   = [old_gauntlet_rubygems_rb, old_builder_rb, old_format_rb, old_bundler_c_rb, old_bundler_ci]
    files_that_stay = [securerandom_rb, engine_defaults_rb, os_defaults_rb]

    create_dummy_files(files_that_go + files_that_stay)

    @cmd.remove_old_lib_files lib

    files_that_go.each {|file| refute_path_exists file }

    files_that_stay.each {|file| assert_path_exists file }
  end

  def test_remove_old_man_files
    man = File.join @install_dir, 'man'

    ruby_1             = File.join man, 'man1', 'ruby.1'
    bundle_b_1         = File.join man, 'man1', 'bundle-b.1'
    bundle_b_1_txt     = File.join man, 'man1', 'bundle-b.1.txt'
    bundle_old_b_1     = File.join man, 'man1', 'bundle-old_b.1'
    bundle_old_b_1_txt = File.join man, 'man1', 'bundle-old_b.1.txt'
    gemfile_5          = File.join man, 'man5', 'gemfile.5'
    gemfile_5_txt      = File.join man, 'man5', 'gemfile.5.txt'

    files_that_go   = [bundle_old_b_1, bundle_old_b_1_txt]
    files_that_stay = [ruby_1, bundle_b_1, bundle_b_1_txt, gemfile_5, gemfile_5_txt]

    create_dummy_files(files_that_go + files_that_stay)

    @cmd.remove_old_man_files man

    files_that_go.each {|file| refute_path_exists file }

    files_that_stay.each {|file| assert_path_exists file }
  end

  def test_show_release_notes
    @default_external = @ui.outs.external_encoding
    @ui.outs.set_encoding Encoding::US_ASCII

    @cmd.options[:previous_version] = Gem::Version.new '2.0.2'

    File.open 'History.txt', 'w' do |io|
      io.puts <<-HISTORY_TXT
# coding: UTF-8

=== #{Gem::VERSION} / 2013-03-26

* Bug fixes:
  * Fixed release note display for LANG=C when installing rubygems
  * π is tasty

=== 2.0.2 / 2013-03-06

* Bug fixes:
  * Other bugs fixed

=== 2.0.1 / 2013-03-05

* Bug fixes:
  * Yet more bugs fixed
      HISTORY_TXT
    end

    use_ui @ui do
      @cmd.show_release_notes
    end

    expected = <<-EXPECTED
=== #{Gem::VERSION} / 2013-03-26

* Bug fixes:
  * Fixed release note display for LANG=C when installing rubygems
  * π is tasty

    EXPECTED

    output = @ui.output
    output.force_encoding Encoding::UTF_8

    assert_equal expected, output
  ensure
    @ui.outs.set_encoding @default_external if @default_external
  end

  private

  def create_dummy_files(list)
    list.each do |file|
      FileUtils.mkdir_p File.dirname(file)

      File.open file, 'w' do |io|
        io.puts "# #{File.basename(file)}"
      end
    end
  end

  def gem_install(name)
    gem = util_spec name do |s|
      s.executables = [name]
      s.files = %W[bin/#{name}]
    end
    write_file File.join @tempdir, 'bin', name do |f|
      f.puts '#!/usr/bin/ruby'
    end
    install_gem gem
    File.join @gemhome, 'bin', name
  end

  def gem_install_with_plugin(name)
    gem = util_spec name do |s|
      s.files = %W[lib/rubygems_plugin.rb]
    end
    write_file File.join @tempdir, 'lib', 'rubygems_plugin.rb' do |f|
      f.puts "require '#{gem.plugins.first}'"
    end
    install_gem gem

    File.join Gem.plugindir, "#{name}_plugin.rb"
  end

  def default_gem_bin_path
    File.join @install_dir, 'bin', 'gem'
  end

  def default_bundle_bin_path
    File.join @install_dir, 'bin', 'bundle'
  end

end unless Gem.java_platform?
