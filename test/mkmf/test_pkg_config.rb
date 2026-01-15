# frozen_string_literal: false
require_relative 'base'
require 'shellwords'

class TestMkmfPkgConfig < TestMkmf
  PKG_CONFIG = config_string("PKG_CONFIG") {|path| find_executable0(path)}

  def setup
    super

    if PKG_CONFIG
      @fixtures_dir = File.join(Dir.pwd, "fixtures")
      @fixtures_lib_dir = File.join(@fixtures_dir, "lib")
      @fixtures_inc_dir = File.join(@fixtures_dir, "include")

      FileUtils.mkdir(@fixtures_dir)
      File.write("fixtures/test1.pc", <<~EOF)
        libdir=#{@fixtures_lib_dir}
        includedir=#{@fixtures_inc_dir}

        Name: test1
        Description: Test for mkmf pkg-config method
        Version: 1.2.3
        Libs: -L${libdir} -ltest1-public
        Libs.private: -ltest1-private
        Cflags: -I${includedir}/cflags-I --cflags-other
      EOF

      @pkg_config_path, ENV["PKG_CONFIG_PATH"] = ENV["PKG_CONFIG_PATH"], @fixtures_dir
    end
  end

  def teardown
    if PKG_CONFIG
      ENV["PKG_CONFIG_PATH"] = @pkg_config_path
    end

    super
  end

  def test_pkgconfig_with_option_returns_nil_on_error
    pend("skipping because pkg-config is not installed") unless PKG_CONFIG
    assert_nil(pkg_config("package-does-not-exist", "exists"), MKMFLOG)
  end

  def test_pkgconfig_with_libs_option_returns_output
    pend("skipping because pkg-config is not installed") unless PKG_CONFIG
    expected = ["-L#{@fixtures_lib_dir}", "-ltest1-public"].sort
    actual = pkg_config("test1", "libs")
    assert_equal_sorted(expected, actual, MKMFLOG)
  end

  def test_pkgconfig_with_cflags_option_returns_output
    pend("skipping because pkg-config is not installed") unless PKG_CONFIG
    expected = ["--cflags-other", "-I#{@fixtures_inc_dir}/cflags-I"].sort
    actual = pkg_config("test1", "cflags")
    assert_equal_sorted(expected, actual, MKMFLOG)
  end

  def test_pkgconfig_with_multiple_options
    pend("skipping because pkg-config is not installed") unless PKG_CONFIG
    expected = ["-L#{@fixtures_lib_dir}", "-ltest1-public", "-ltest1-private"].sort
    actual = pkg_config("test1", "libs", "static")
    assert_equal_sorted(expected, actual, MKMFLOG)
  end

  private def assert_equal_sorted(expected, actual, msg = nil)
    actual = actual.shellsplit.sort if actual
    assert_equal(expected, actual, msg)
  end
end
