# coding: UTF-8

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

    assert_match(/^#{Gem.ruby} extconf.rb/, output[0])
    assert_equal "creating Makefile\n", output[1]
    assert_contains_make_command 'clean', output[2]
    assert_contains_make_command '', output[4]
    assert_contains_make_command 'install', output[6]
    assert_empty Dir.glob(File.join(@ext, 'siteconf*.rb'))
  end

  def test_class_build_rbconfig_make_prog
    configure_args = RbConfig::CONFIG['configure_args']

    File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
      extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
    end

    output = []

    Dir.chdir @ext do
      Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
    end

    assert_equal "creating Makefile\n", output[1]
    assert_contains_make_command 'clean', output[2]
    assert_contains_make_command '', output[4]
    assert_contains_make_command 'install', output[6]
  ensure
    RbConfig::CONFIG['configure_args'] = configure_args
  end

  def test_class_build_env_make
    configure_args, env_make = RbConfig::CONFIG['configure_args'], ENV.delete('make')
    RbConfig::CONFIG['configure_args'] = ''
    ENV['make'] = 'anothermake'

    File.open File.join(@ext, 'extconf.rb'), 'w' do |extconf|
      extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
    end

    output = []

    assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::ExtConfBuilder.build 'extconf.rb', nil, @dest_path, output
      end
    end

    assert_equal "creating Makefile\n",   output[1]
    assert_contains_make_command 'clean', output[2]
  ensure
    RbConfig::CONFIG['configure_args'] = configure_args
    ENV['make'] = env_make
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

    assert_equal("#{Gem.ruby} extconf.rb", output[0])
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

    assert_contains_make_command 'clean', output[2]
    assert_contains_make_command '', output[4]
    assert_contains_make_command 'install', output[6]
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

    assert_contains_make_command 'clean', output[0]
    assert_contains_make_command '', output[2]
    assert_contains_make_command 'install', output[4]
  end

  def test_class_make_no_Makefile
    error = assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::ExtConfBuilder.make @ext, ['output']
      end
    end

    assert_equal 'Makefile not found', error.message
  end

end

