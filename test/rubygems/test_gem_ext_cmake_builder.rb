# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"

class TestGemExtCmakeBuilder < Gem::TestCase
  def setup
    super

    # Details: https://github.com/ruby/rubygems/issues/1270#issuecomment-177368340
    pend "CmakeBuilder doesn't work on Windows." if Gem.win_platform?

    require "open3"

    begin
      _, status = Open3.capture2e("cmake")
      pend "cmake not present" unless status.success?
    rescue Errno::ENOENT
      pend "cmake not present"
    end

    @ext = File.join @tempdir, "ext"
    @dest_path = File.join @tempdir, "prefix"

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_self_build
    File.open File.join(@ext, "CMakeLists.txt"), "w" do |cmakelists|
      cmakelists.write <<-EO_CMAKE
cmake_minimum_required(VERSION 3.26)
project(self_build NONE)
install (FILES test.txt DESTINATION bin)
      EO_CMAKE
    end

    FileUtils.touch File.join(@ext, "test.txt")

    output = []

    builder = Gem::Ext::CmakeBuilder.new
    builder.build nil, @dest_path, output, [], @dest_path, @ext

    output = output.join "\n"

    assert_match(/^current directory: #{Regexp.escape @ext}/, output)
    assert_match(/cmake.*-DCMAKE_RUNTIME_OUTPUT_DIRECTORY\\=#{Regexp.escape @dest_path}/, output)
    assert_match(/cmake.*-DCMAKE_LIBRARY_OUTPUT_DIRECTORY\\=#{Regexp.escape @dest_path}/, output)
    assert_match(/#{Regexp.escape @ext}/, output)
  end

  def test_self_build_presets
    File.open File.join(@ext, "CMakeLists.txt"), "w" do |cmakelists|
      cmakelists.write <<-EO_CMAKE
cmake_minimum_required(VERSION 3.26)
project(self_build NONE)
install (FILES test.txt DESTINATION bin)
      EO_CMAKE
    end

    File.open File.join(@ext, "CMakePresets.json"), "w" do |presets|
      presets.write <<-EO_CMAKE
{
  "version": 6,
  "configurePresets": [
    {
      "name": "debug",
      "displayName": "Debug",
      "generator": "Ninja",
      "binaryDir": "build/debug",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug"
      }
    },
    {
      "name": "release",
      "displayName": "Release",
      "generator": "Ninja",
      "binaryDir": "build/release",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Release"
      }
    }
  ]
}
      EO_CMAKE
    end

    FileUtils.touch File.join(@ext, "test.txt")

    output = []

    builder = Gem::Ext::CmakeBuilder.new
    builder.build nil, @dest_path, output, [], @dest_path, @ext

    output = output.join "\n"

    assert_match(/The gem author provided a list of presets that can be used to build the gem./, output)
    assert_match(/Available configure presets/, output)
    assert_match(/\"debug\"   - Debug/, output)
    assert_match(/\"release\" - Release/, output)
    assert_match(/^current directory: #{Regexp.escape @ext}/, output)
    assert_match(/cmake.*-DCMAKE_RUNTIME_OUTPUT_DIRECTORY\\=#{Regexp.escape @dest_path}/, output)
    assert_match(/cmake.*-DCMAKE_LIBRARY_OUTPUT_DIRECTORY\\=#{Regexp.escape @dest_path}/, output)
    assert_match(/#{Regexp.escape @ext}/, output)
  end

  def test_self_build_fail
    output = []

    builder = Gem::Ext::CmakeBuilder.new
    error = assert_raise Gem::InstallError do
      builder.build nil, @dest_path, output, [], @dest_path, @ext
    end

    assert_match "cmake_configure failed", error.message

    shell_error_msg = /(CMake Error: .*)/
    output = output.join "\n"
    assert_match(/#{shell_error_msg}/, output)
    assert_match(/CMake Error: The source directory .* does not appear to contain CMakeLists.txt./, output)
  end

  def test_self_build_has_makefile
    File.open File.join(@ext, "CMakeLists.txt"), "w" do |cmakelists|
      cmakelists.write <<-EO_CMAKE
cmake_minimum_required(VERSION 3.26)
project(self_build NONE)
install (FILES test.txt DESTINATION bin)
      EO_CMAKE
    end

    output = []

    builder = Gem::Ext::CmakeBuilder.new
    builder.build nil, @dest_path, output, [], @dest_path, @ext

    output = output.join "\n"

    # The default generator will create a Makefile in the build directory
    makefile = File.join(@ext, "build", "Makefile")
    assert(File.exist?(makefile))
  end
end
