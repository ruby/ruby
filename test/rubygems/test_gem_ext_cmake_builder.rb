# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/ext'

class TestGemExtCmakeBuilder < Gem::TestCase
  def setup
    super

    # Details: https://github.com/rubygems/rubygems/issues/1270#issuecomment-177368340
    pend "CmakeBuilder doesn't work on Windows." if Gem.win_platform?

    begin
      _, status = Open3.capture2e('cmake')
      pend 'cmake not present' unless status.success?
    rescue Errno::ENOENT
      pend 'cmake not present'
    end

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_self_build
    File.open File.join(@ext, 'CMakeLists.txt'), 'w' do |cmakelists|
      cmakelists.write <<-EO_CMAKE
cmake_minimum_required(VERSION 2.6)
project(self_build NONE)
install (FILES test.txt DESTINATION bin)
      EO_CMAKE
    end

    FileUtils.touch File.join(@ext, 'test.txt')

    output = []

    Gem::Ext::CmakeBuilder.build nil, @dest_path, output, [], nil, @ext

    output = output.join "\n"

    assert_match %r{^cmake \. -DCMAKE_INSTALL_PREFIX\\=#{Regexp.escape @dest_path}}, output
    assert_match %r{#{Regexp.escape @ext}}, output
    assert_contains_make_command '', output
    assert_contains_make_command 'install', output
    assert_match %r{test\.txt}, output
  end

  def test_self_build_fail
    output = []

    error = assert_raise Gem::InstallError do
      Gem::Ext::CmakeBuilder.build nil, @dest_path, output, [], nil, @ext
    end

    output = output.join "\n"

    shell_error_msg = %r{(CMake Error: .*)}

    assert_match 'cmake failed', error.message

    assert_match %r{^cmake . -DCMAKE_INSTALL_PREFIX\\=#{Regexp.escape @dest_path}}, output
    assert_match %r{#{shell_error_msg}}, output
  end

  def test_self_build_has_makefile
    File.open File.join(@ext, 'Makefile'), 'w' do |makefile|
      makefile.puts "all:\n\t@echo ok\ninstall:\n\t@echo ok"
    end

    output = []

    Gem::Ext::CmakeBuilder.build nil, @dest_path, output, [], nil, @ext

    output = output.join "\n"

    assert_contains_make_command '', output
    assert_contains_make_command 'install', output
  end
end
