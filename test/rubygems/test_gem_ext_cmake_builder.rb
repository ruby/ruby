require 'rubygems/test_case'
require 'rubygems/ext'

class TestGemExtCmakeBuilder < Gem::TestCase

  def setup
    super

    `cmake #{Gem::Ext::Builder.redirector}`

    skip 'cmake not present' unless $?.success?

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_self_build
    File.open File.join(@ext, 'CMakeLists.txt'), 'w' do |cmakelists|
      cmakelists.write <<-eo_cmake
cmake_minimum_required(VERSION 2.8)
install (FILES test.txt DESTINATION bin)
      eo_cmake
    end
    File.open File.join(@ext, 'test.txt'), 'w' do |testfile|
    end

    output = []

    Dir.chdir @ext do
      Gem::Ext::CmakeBuilder.build nil, nil, @dest_path, output
    end

    assert_equal "cmake . -DCMAKE_INSTALL_PREFIX=#{@dest_path}", output.shift
    assert_match(/#{@ext}/, output.shift)
    assert_equal make_command, output.shift
    assert_equal "", output.shift
    assert_equal make_command + " install", output.shift
    assert_match(/test\.txt/, output.shift)
  end

  def test_self_build_fail
    output = []

    error = assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::CmakeBuilder.build nil, nil, @dest_path, output
      end
    end

    shell_error_msg = %r{(CMake Error: .*)}
    sh_prefix_cmake = "cmake . -DCMAKE_INSTALL_PREFIX="

    expected = %r(cmake failed:

#{Regexp.escape sh_prefix_cmake}#{Regexp.escape @dest_path}
#{shell_error_msg}
)

    assert_match expected, error.message

    assert_equal "#{sh_prefix_cmake}#{@dest_path}", output.shift
    assert_match %r(#{shell_error_msg}), output.shift
    assert_equal true, output.empty?
  end

  def test_self_build_has_makefile
    File.open File.join(@ext, 'Makefile'), 'w' do |makefile|
      makefile.puts "all:\n\t@echo ok\ninstall:\n\t@echo ok"
    end

    output = []
    Dir.chdir @ext do
      Gem::Ext::CmakeBuilder.build nil, nil, @dest_path, output
    end

    assert_equal make_command, output[0]
    assert_equal "#{make_command} install", output[2]
  end

end

