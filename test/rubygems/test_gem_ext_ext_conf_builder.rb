# coding: UTF-8
# frozen_string_literal: true

require 'rubygems/test_case'
require 'rubygems/ext'

class TestGemExtExtConfBuilder < Gem::TestCase

  def setup
    super

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_class_build
    if vc_windows? && !nmake_found?
      skip("test_class_build skipped - nmake not found")
    end

    File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
      extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
    end

    output = []

    Dir.chdir @ext do
      result =
        Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output

      assert_same result, output
    end

    assert_match(/^current directory:/, output[0])
    assert_match(/^#{Gem.ruby}.* extconf.rb/, output[1])
    assert_equal "creating Makefile\n", output[2]
    assert_match(/^current directory:/, output[3])
    assert_contains_make_command 'clean', output[4]
    assert_contains_make_command '', output[7]
    assert_contains_make_command 'install', output[10]
    assert_empty Dir.glob(File.join(@ext, 'siteconf*.rb'))
  end

  def test_class_build_rbconfig_make_prog
    configure_args do

      File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
        extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
      end

      output = []

      Dir.chdir @ext do
        Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
      end

      assert_equal "creating Makefile\n", output[2]
      assert_contains_make_command 'clean', output[4]
      assert_contains_make_command '', output[7]
      assert_contains_make_command 'install', output[10]
    end
  end

  def test_class_build_env_make
    env_make = ENV.delete 'MAKE'
    ENV['MAKE'] = 'anothermake'

    configure_args '' do
      File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
        extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
      end

      output = []

      assert_raises Gem::InstallError do
        Dir.chdir @ext do
          Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
        end
      end

      assert_equal "creating Makefile\n",   output[2]
      assert_contains_make_command 'clean', output[4]
    end
  ensure
    ENV['MAKE'] = env_make
  end

  def test_class_build_extconf_fail
    if vc_windows? && !nmake_found?
      skip("test_class_build_extconf_fail skipped - nmake not found")
    end

    File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
      extconf.puts "require 'mkmf'"
      extconf.puts "have_library 'nonexistent' or abort 'need libnonexistent'"
      extconf.puts "create_makefile 'foo'"
    end

    output = []

    error = assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
      end
    end

    assert_equal 'extconf failed, exit code 1', error.message

    assert_match(/^#{Gem.ruby}.* extconf.rb/, output[1])
    assert_match(File.join(@dest_path, 'mkmf.log'), output[4])

    assert_path_exists File.join @dest_path, 'mkmf.log'
  end

  def test_class_build_unconventional
    if vc_windows? && !nmake_found?
      skip("test_class_build skipped - nmake not found")
    end

    File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
      extconf.puts <<-'EXTCONF'
include RbConfig

ruby =
  if ENV['RUBY'] then
    ENV['RUBY']
  else
    ruby_exe = "#{CONFIG['RUBY_INSTALL_NAME']}#{CONFIG['EXEEXT']}"
    File.join CONFIG['bindir'], ruby_exe
  end

open 'Makefile', 'w' do |io|
  io.write <<-Makefile
clean: ruby
all: ruby
install: ruby

ruby:
\t#{ruby} -e0

  Makefile
end
      EXTCONF
    end

    output = []

    Dir.chdir @ext do
      Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
    end

    assert_contains_make_command 'clean', output[4]
    assert_contains_make_command '', output[7]
    assert_contains_make_command 'install', output[10]
    assert_empty Dir.glob(File.join(@ext, 'siteconf*.rb'))
  end

  def test_class_make
    if vc_windows? && !nmake_found?
      skip("test_class_make skipped - nmake not found")
    end

    output = []
    makefile_path = File.join(@ext, 'Makefile')
    File.open makefile_path, 'w' do |makefile|
      makefile.puts "# π"
      makefile.puts "RUBYARCHDIR = $(foo)$(target_prefix)"
      makefile.puts "RUBYLIBDIR = $(bar)$(target_prefix)"
      makefile.puts "clean:"
      makefile.puts "all:"
      makefile.puts "install:"
    end

    Dir.chdir @ext do
      Gem::Ext::ExtConfBuilder.make @ext, output
    end

    assert_contains_make_command 'clean', output[1]
    assert_contains_make_command '', output[4]
    assert_contains_make_command 'install', output[7]
  end

  def test_class_make_no_Makefile
    error = assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::ExtConfBuilder.make @ext, ['output']
      end
    end

    assert_equal 'Makefile not found', error.message
  end

  def configure_args args = nil
    configure_args = RbConfig::CONFIG['configure_args']
    RbConfig::CONFIG['configure_args'] = args if args

    yield

  ensure
    if configure_args then
      RbConfig::CONFIG['configure_args'] = configure_args
    else
      RbConfig::CONFIG.delete 'configure_args'
    end
  end

end

