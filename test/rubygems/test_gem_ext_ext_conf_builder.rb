# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"

class TestGemExtExtConfBuilder < Gem::TestCase
  def setup
    super

    @ext = File.join @tempdir, "ext"
    @dest_path = File.join @tempdir, "prefix"

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_class_build
    if Gem.java_platform?
      pend("failing on jruby")
    end

    if vc_windows? && !nmake_found?
      pend("test_class_build skipped - nmake not found")
    end

    File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
      extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
    end

    output = []

    result = Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext

    assert_same result, output

    assert_match(/^current directory:/, output[0])
    assert_match(/^#{Gem.ruby}.* extconf.rb/, output[1])
    assert_equal "creating Makefile\n", output[2]
    assert_match(/^current directory:/, output[3])
    assert_contains_make_command "clean", output[4]
    assert_contains_make_command "", output[7]
    assert_contains_make_command "install", output[10]
    assert_empty Dir.glob(File.join(@ext, "siteconf*.rb"))
    assert_empty Dir.glob(File.join(@ext, ".gem.*"))
  end

  def test_class_build_rbconfig_make_prog
    if Gem.java_platform?
      pend("failing on jruby")
    end

    configure_args do
      File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
        extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
      end

      output = []

      Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext

      assert_equal "creating Makefile\n", output[2]
      assert_contains_make_command "clean", output[4]
      assert_contains_make_command "", output[7]
      assert_contains_make_command "install", output[10]
    end
  end

  def test_class_build_env_make
    env_make = ENV.delete "make"
    ENV["make"] = nil

    env_large_make = ENV.delete "MAKE"
    ENV["MAKE"] = "anothermake"

    if Gem.java_platform?
      pend("failing on jruby")
    end

    configure_args "" do
      File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
        extconf.puts "require 'mkmf'\ncreate_makefile 'foo'"
      end

      output = []

      assert_raise Gem::InstallError do
        Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext
      end

      assert_equal "creating Makefile\n",   output[2]
      assert_contains_make_command "clean", output[4]
    end
  ensure
    ENV["MAKE"] = env_large_make
    ENV["make"] = env_make
  end

  def test_class_build_extconf_fail
    if vc_windows? && !nmake_found?
      pend("test_class_build_extconf_fail skipped - nmake not found")
    end

    File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
      extconf.puts "require 'mkmf'"
      extconf.puts "have_library 'nonexistent' or abort 'need libnonexistent'"
      extconf.puts "create_makefile 'foo'"
    end

    output = []

    error = assert_raise Gem::InstallError do
      Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext
    end

    assert_equal "extconf failed, exit code 1", error.message

    assert_match(/^#{Gem.ruby}.* extconf.rb/, output[1])
    assert_match(File.join(@dest_path, "mkmf.log"), output[4])
    assert_includes(output, "To see why this extension failed to compile, please check the mkmf.log which can be found here:\n")

    assert_path_exist File.join @dest_path, "mkmf.log"
  end

  def test_class_build_extconf_success_without_warning
    if vc_windows? && !nmake_found?
      pend("test_class_build_extconf_fail skipped - nmake not found")
    end

    File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
      extconf.puts "require 'mkmf'"
      extconf.puts "File.open('mkmf.log', 'w'){|f| f.write('a')}"
      extconf.puts "create_makefile 'foo'"
    end

    output = []

    Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext

    refute_includes(output, "To see why this extension failed to compile, please check the mkmf.log which can be found here:\n")

    assert_path_exist File.join @dest_path, "mkmf.log"
  end

  def test_class_build_unconventional
    if vc_windows? && !nmake_found?
      pend("test_class_build skipped - nmake not found")
    end

    File.open File.join(@ext, "extconf.rb"), "w" do |extconf|
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

    Gem::Ext::ExtConfBuilder.build "extconf.rb", @dest_path, output, [], nil, @ext

    assert_contains_make_command "clean", output[4]
    assert_contains_make_command "", output[7]
    assert_contains_make_command "install", output[10]
    assert_empty Dir.glob(File.join(@ext, "siteconf*.rb"))
  end

  def test_class_make
    if vc_windows? && !nmake_found?
      pend("test_class_make skipped - nmake not found")
    end

    output = []
    makefile_path = File.join(@ext, "Makefile")
    File.open makefile_path, "w" do |makefile|
      makefile.puts "# π"
      makefile.puts "RUBYARCHDIR = $(foo)$(target_prefix)"
      makefile.puts "RUBYLIBDIR = $(bar)$(target_prefix)"
      makefile.puts "clean:"
      makefile.puts "all:"
      makefile.puts "install:"
    end

    Gem::Ext::ExtConfBuilder.make @ext, output, @ext

    assert_contains_make_command "clean", output[1]
    assert_contains_make_command "", output[4]
    assert_contains_make_command "install", output[7]
  end

  def test_class_make_no_Makefile
    error = assert_raise Gem::InstallError do
      Gem::Ext::ExtConfBuilder.make @ext, ["output"], @ext
    end

    assert_equal "Makefile not found", error.message
  end

  def configure_args(args = nil)
    configure_args = RbConfig::CONFIG["configure_args"]
    RbConfig::CONFIG["configure_args"] = args if args

    yield
  ensure
    if configure_args
      RbConfig::CONFIG["configure_args"] = configure_args
    else
      RbConfig::CONFIG.delete "configure_args"
    end
  end
end
