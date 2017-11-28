# coding: UTF-8
# frozen_string_literal: true

require 'rubygems/test_case'
require 'rubygems/commands/setup_command'

class TestGemCommandsSetupCommand < Gem::TestCase

  def setup
    super

    @install_dir = File.join @tempdir, 'install'
    @cmd = Gem::Commands::SetupCommand.new
    @cmd.options[:prefix] = @install_dir

    FileUtils.mkdir_p 'bin'
    FileUtils.mkdir_p 'lib/rubygems/ssl_certs/rubygems.org'

    open 'bin/gem',                   'w' do |io| io.puts '# gem'          end
    open 'lib/rubygems.rb',           'w' do |io| io.puts '# rubygems.rb'  end
    open 'lib/rubygems/test_case.rb', 'w' do |io| io.puts '# test_case.rb' end
    open 'lib/rubygems/ssl_certs/rubygems.org/foo.pem', 'w' do |io| io.puts 'PEM'       end

    FileUtils.mkdir_p 'bundler/exe'
    FileUtils.mkdir_p 'bundler/lib/bundler'

    open 'bundler/exe/bundle',        'w' do |io| io.puts '# bundle'       end
    open 'bundler/lib/bundler.rb',    'w' do |io| io.puts '# bundler.rb'   end
    open 'bundler/lib/bundler/b.rb',  'w' do |io| io.puts '# b.rb'         end

    FileUtils.mkdir_p 'default/gems'

    gemspec = Gem::Specification.new
    gemspec.name = "bundler"
    gemspec.version = "1.16.0"
    gemspec.bindir = "exe"
    gemspec.executables = ["bundle"]

    open 'bundler/bundler.gemspec',   'w' do |io|
      io.puts gemspec.to_ruby
    end

    open(File.join(Gem::Specification.default_specifications_dir, "bundler-1.15.4.gemspec"), 'w') do |io|
      io.puts '# bundler'
    end

    FileUtils.mkdir_p File.join(Gem.default_dir, "specifications")
    open(File.join(Gem.default_dir, "specifications", "bundler-audit-1.0.0.gemspec"), 'w') do |io|
      io.puts '# bundler-audit'
    end

    FileUtils.mkdir_p 'default/gems/bundler-1.15.4'
    FileUtils.mkdir_p 'default/gems/bundler-audit-1.0.0'
  end

  def gem_install name
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

      if Gem::USE_BUNDLER_FOR_GEMDEPS
        assert_path_exists File.join(dir, 'bundler.rb')
        assert_path_exists File.join(dir, 'bundler/b.rb')
      end
    end
  end

  def test_install_default_bundler_gem
    @cmd.extend FileUtils

    @cmd.install_default_bundler_gem

    if Gem.win_platform?
      bundler_spec = Gem::Specification.load("bundler/bundler.gemspec")
      default_spec_path = File.join(Gem::Specification.default_specifications_dir, "#{bundler_spec.full_name}.gemspec")
      spec = Gem::Specification.load(default_spec_path)

      spec.executables.each do |e|
        assert_path_exists File.join(spec.bin_dir, "#{e}.bat")
      end
    end

    default_dir = Gem::Specification.default_specifications_dir

    refute_path_exists File.join(default_dir, "bundler-1.15.4.gemspec")
    refute_path_exists 'default/gems/bundler-1.15.4'

    assert_path_exists File.join(default_dir, "bundler-1.16.0.gemspec")
    assert_path_exists 'default/gems/bundler-1.16.0'

    assert_path_exists File.join(Gem.default_dir, "specifications", "bundler-audit-1.0.0.gemspec")
    assert_path_exists 'default/gems/bundler-audit-1.0.0'
  end if Gem::USE_BUNDLER_FOR_GEMDEPS

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

    open securerandom_rb,    'w' do |io| io.puts '# securerandom.rb'     end

    open old_builder_rb,     'w' do |io| io.puts '# builder.rb'          end
    open old_format_rb,      'w' do |io| io.puts '# format.rb'           end
    open old_bundler_c_rb,   'w' do |io| io.puts '# c.rb'                end

    open engine_defaults_rb, 'w' do |io| io.puts '# jruby.rb'            end
    open os_defaults_rb,     'w' do |io| io.puts '# operating_system.rb' end

    @cmd.remove_old_lib_files lib

    refute_path_exists old_builder_rb
    refute_path_exists old_format_rb
    refute_path_exists old_bundler_c_rb if Gem::USE_BUNDLER_FOR_GEMDEPS

    assert_path_exists securerandom_rb
    assert_path_exists engine_defaults_rb
    assert_path_exists os_defaults_rb
  end

  def test_show_release_notes
    @default_external = nil
    if Object.const_defined? :Encoding
      @default_external = @ui.outs.external_encoding
      @ui.outs.set_encoding Encoding::US_ASCII
    end

    @cmd.options[:previous_version] = Gem::Version.new '2.0.2'

    open 'History.txt', 'w' do |io|
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
    output.force_encoding Encoding::UTF_8 if Object.const_defined? :Encoding

    assert_equal expected, output
  ensure
    @ui.outs.set_encoding @default_external if @default_external
  end

end
