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
    end
  end

  def test_remove_old_lib_files
    lib                   = File.join @install_dir, 'lib'
    lib_rubygems          = File.join lib, 'rubygems'
    lib_rubygems_defaults = File.join lib_rubygems, 'defaults'

    securerandom_rb    = File.join lib, 'securerandom.rb'

    engine_defaults_rb = File.join lib_rubygems_defaults, 'jruby.rb'
    os_defaults_rb     = File.join lib_rubygems_defaults, 'operating_system.rb'

    old_builder_rb     = File.join lib_rubygems, 'builder.rb'
    old_format_rb      = File.join lib_rubygems, 'format.rb'

    FileUtils.mkdir_p lib_rubygems_defaults

    open securerandom_rb,    'w' do |io| io.puts '# securerandom.rb'     end

    open old_builder_rb,     'w' do |io| io.puts '# builder.rb'          end
    open old_format_rb,      'w' do |io| io.puts '# format.rb'           end

    open engine_defaults_rb, 'w' do |io| io.puts '# jruby.rb'            end
    open os_defaults_rb,     'w' do |io| io.puts '# operating_system.rb' end

    @cmd.remove_old_lib_files lib

    refute_path_exists old_builder_rb
    refute_path_exists old_format_rb

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
