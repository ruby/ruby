# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/ext'

class TestGemExtConfigureBuilder < Gem::TestCase

  def setup
    super

    @makefile_body =
      "clean:\n\t@echo ok\nall:\n\t@echo ok\ninstall:\n\t@echo ok"

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_self_build
    skip("test_self_build skipped on MS Windows (VC++)") if vc_windows?

    File.open File.join(@ext, './configure'), 'w' do |configure|
      configure.puts "#!/bin/sh\necho \"#{@makefile_body}\" > Makefile"
    end

    output = []

    Dir.chdir @ext do
      Gem::Ext::ConfigureBuilder.build nil, nil, @dest_path, output
    end

    assert_match(/^current directory:/, output.shift)
    assert_equal "sh ./configure --prefix=#{@dest_path}", output.shift
    assert_equal "", output.shift
    assert_match(/^current directory:/, output.shift)
    assert_contains_make_command 'clean', output.shift
    assert_match(/^ok$/m, output.shift)
    assert_match(/^current directory:/, output.shift)
    assert_contains_make_command '', output.shift
    assert_match(/^ok$/m, output.shift)
    assert_match(/^current directory:/, output.shift)
    assert_contains_make_command 'install', output.shift
    assert_match(/^ok$/m, output.shift)
  end

  def test_self_build_fail
    skip("test_self_build_fail skipped on MS Windows (VC++)") if vc_windows?
    output = []

    error = assert_raises Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::ConfigureBuilder.build nil, nil, @dest_path, output
      end
    end

    shell_error_msg = %r{(\./configure: .*)|((?:Can't|cannot) open \./configure(?:: No such file or directory)?)}
    sh_prefix_configure = "sh ./configure --prefix="

    assert_match 'configure failed', error.message

    assert_match(/^current directory:/, output.shift)
    assert_equal "#{sh_prefix_configure}#{@dest_path}", output.shift
    assert_match %r(#{shell_error_msg}), output.shift
    assert_equal true, output.empty?
  end

  def test_self_build_has_makefile
    if vc_windows? && !nmake_found?
      skip("test_self_build_has_makefile skipped - nmake not found")
    end

    File.open File.join(@ext, 'Makefile'), 'w' do |makefile|
      makefile.puts @makefile_body
    end

    output = []
    Dir.chdir @ext do
      Gem::Ext::ConfigureBuilder.build nil, nil, @dest_path, output
    end

    assert_contains_make_command 'clean', output[1]
    assert_contains_make_command '', output[4]
    assert_contains_make_command 'install', output[7]
  end

end
