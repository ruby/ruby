# coding: UTF-8
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

    FileUtils.mkdir_p 'bin'
    FileUtils.mkdir_p 'lib/rubygems/ssl_certs/rubygems.org'

    File.open 'bin/gem',                   'w' do
      |io| io.puts '# gem'
    end

    File.open 'lib/rubygems.rb',           'w' do |io|
      io.puts '# rubygems.rb'
    end

    File.open 'lib/rubygems/test_case.rb', 'w' do |io|
      io.puts '# test_case.rb'
    end

    File.open 'lib/rubygems/ssl_certs/rubygems.org/foo.pem', 'w' do |io|
      io.puts 'PEM'
    end

    FileUtils.mkdir_p 'bundler/exe'
    FileUtils.mkdir_p 'bundler/lib/bundler'

    File.open 'bundler/exe/bundle',        'w' do |io|
      io.puts '# bundle'
    end

    File.open 'bundler/lib/bundler.rb',    'w' do |io|
      io.puts '# bundler.rb'
    end

    File.open 'bundler/lib/bundler/b.rb',  'w' do |io|
      io.puts '# b.rb'
    end

    FileUtils.mkdir_p 'default/gems'

    gemspec = Gem::Specification.new
    gemspec.author = "Us"
    gemspec.name = "bundler"
    gemspec.version = BUNDLER_VERS
    gemspec.bindir = "exe"
    gemspec.executables = ["bundle"]

    File.open 'bundler/bundler.gemspec',   'w' do |io|
      io.puts gemspec.to_ruby
    end

    open(File.join(Gem::Specification.default_specifications_dir, "bundler-1.15.4.gemspec"), 'w') do |io|
      gemspec.version = "1.15.4"
      io.puts gemspec.to_ruby
    end

    FileUtils.mkdir_p File.join(Gem.default_dir, "specifications")

    open(File.join(Gem.default_dir, "specifications", "bundler-#{BUNDLER_VERS}.gemspec"), 'w') do |io|
      io.puts "# bundler-#{BUNDLER_VERS}"
    end

    open(File.join(Gem.default_dir, "specifications", "bundler-audit-1.0.0.gemspec"), 'w') do |io|
      io.puts '# bundler-audit'
    end

    FileUtils.mkdir_p 'default/gems/bundler-1.15.4'
    FileUtils.mkdir_p 'default/gems/bundler-audit-1.0.0'
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

  def test_env_shebang_flag
    gem_bin_path = gem_install 'a'
    write_file gem_bin_path do |io|
      io.puts 'I changed it!'
    end

    @cmd.options[:document] = []
    @cmd.options[:env_shebang] = true
    @cmd.execute

    gem_exec = sprintf Gem.default_exec_format, 'gem'
    default_gem_bin_path = File.join @install_dir, 'bin', gem_exec
    bundle_exec = sprintf Gem.default_exec_format, 'bundle'
    default_bundle_bin_path = File.join @install_dir, 'bin', bundle_exec
    ruby_exec = sprintf Gem.default_exec_format, 'ruby'

    if Gem.win_platform?
      assert_match %r%\A#!\s*#{ruby_exec}%, File.read(default_gem_bin_path)
      assert_match %r%\A#!\s*#{ruby_exec}%, File.read(default_bundle_bin_path)
      assert_match %r%\A#!\s*#{ruby_exec}%, File.read(gem_bin_path)
    else
      assert_match %r%\A#!/usr/bin/env #{ruby_exec}%, File.read(default_gem_bin_path)
      assert_match %r%\A#!/usr/bin/env #{ruby_exec}%, File.read(default_bundle_bin_path)
      assert_match %r%\A#!/usr/bin/env #{ruby_exec}%, File.read(gem_bin_path)
    end
  end

  def test_pem_files_in
    assert_equal %w[rubygems/ssl_certs/rubygems.org/foo.pem],
                 @cmd.pem_files_in('lib').sort
  end

  def test_rb_files_in
    assert_equal %w[rubygems.rb rubygems/test_case.rb],
                 @cmd.rb_files_in('lib').sort
  end

  def test_install_lib
    @cmd.extend FileUtils

    Dir.mktmpdir 'lib' do |dir|
      @cmd.install_lib dir

      assert_path_exists File.join(dir, 'rubygems.rb')
      assert_path_exists File.join(dir, 'rubygems/ssl_certs/rubygems.org/foo.pem')

      assert_path_exists File.join(dir, 'bundler.rb')
      assert_path_exists File.join(dir, 'bundler/b.rb')
    end
  end

  def test_install_default_bundler_gem
    @cmd.extend FileUtils

    bin_dir = File.join(@gemhome, 'bin')
    @cmd.install_default_bundler_gem bin_dir

    bundler_spec = Gem::Specification.load("bundler/bundler.gemspec")
    default_spec_path = File.join(Gem::Specification.default_specifications_dir, "#{bundler_spec.full_name}.gemspec")
    spec = Gem::Specification.load(default_spec_path)

    spec.executables.each do |e|
      if Gem.win_platform?
        assert_path_exists File.join(bin_dir, "#{e}.bat")
      end

      assert_path_exists File.join bin_dir, e
    end

    default_dir = Gem::Specification.default_specifications_dir

    # expect to remove other versions of bundler gemspecs on default specification directory.
    refute_path_exists File.join(default_dir, "bundler-1.15.4.gemspec")
    assert_path_exists File.join(default_dir, "bundler-#{BUNDLER_VERS}.gemspec")

    # expect to not remove bundler-* gemspecs.
    assert_path_exists File.join(Gem.default_dir, "specifications", "bundler-audit-1.0.0.gemspec")

    # expect to remove normal gem that was same version. because it's promoted default gems.
    refute_path_exists File.join(Gem.default_dir, "specifications", "bundler-#{BUNDLER_VERS}.gemspec")

    # expect to install default gems. It location was `site_ruby` directory on real world.
    assert_path_exists "default/gems/bundler-#{BUNDLER_VERS}"

    # expect to not remove other versions of bundler on `site_ruby`
    assert_path_exists 'default/gems/bundler-1.15.4'

    # TODO: We need to assert to remove same version of bundler on gem_dir directory(It's not site_ruby dir)

    # expect to not remove bundler-* direcotyr.
    assert_path_exists 'default/gems/bundler-audit-1.0.0'
  end

  def test_remove_old_lib_files
    lib                   = File.join @install_dir, 'lib'
    lib_rubygems          = File.join lib, 'rubygems'
    lib_bundler           = File.join lib, 'bundler'
    lib_rubygems_defaults = File.join lib_rubygems, 'defaults'

    securerandom_rb    = File.join lib, 'securerandom.rb'

    engine_defaults_rb = File.join lib_rubygems_defaults, 'jruby.rb'
    os_defaults_rb     = File.join lib_rubygems_defaults, 'operating_system.rb'

    old_builder_rb     = File.join lib_rubygems, 'builder.rb'
    old_format_rb      = File.join lib_rubygems, 'format.rb'
    old_bundler_c_rb   = File.join lib_bundler,  'c.rb'

    FileUtils.mkdir_p lib_rubygems_defaults
    FileUtils.mkdir_p lib_bundler

    File.open securerandom_rb,    'w' do |io|
      io.puts '# securerandom.rb'
    end

    File.open old_builder_rb,     'w' do |io|
      io.puts '# builder.rb'
    end

    File.open old_format_rb,      'w' do |io|
      io.puts '# format.rb'
    end

    File.open old_bundler_c_rb,   'w' do |io|
      io.puts '# c.rb'
    end

    File.open engine_defaults_rb, 'w' do |io|
      io.puts '# jruby.rb'
    end

    File.open os_defaults_rb,     'w' do |io|
      io.puts '# operating_system.rb'
    end

    @cmd.remove_old_lib_files lib

    refute_path_exists old_builder_rb
    refute_path_exists old_format_rb
    refute_path_exists old_bundler_c_rb

    assert_path_exists securerandom_rb
    assert_path_exists engine_defaults_rb
    assert_path_exists os_defaults_rb
  end

  def test_show_release_notes
    @default_external = @ui.outs.external_encoding
    @ui.outs.set_encoding Encoding::US_ASCII

    @cmd.options[:previous_version] = Gem::Version.new '2.0.2'

    File.open 'History.txt', 'w' do |io|
      io.puts <<-History_txt
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
      History_txt
    end

    use_ui @ui do
      @cmd.show_release_notes
    end

    expected = <<-EXPECTED
=== #{Gem::VERSION} / 2013-03-26

* Bug fixes:
  * Fixed release note display for LANG=C when installing rubygems
  * π is tasty

=== 2.0.2 / 2013-03-06

* Bug fixes:
  * Other bugs fixed

    EXPECTED

    output = @ui.output
    output.force_encoding Encoding::UTF_8

    assert_equal expected, output
  ensure
    @ui.outs.set_encoding @default_external if @default_external
  end

end
