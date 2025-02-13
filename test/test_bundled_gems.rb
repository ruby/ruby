require_relative "rubygems/helper"
require "rubygems"
require "bundled_gems"

class TestBundlerGem < Gem::TestCase
  def setup
    Gem::BUNDLED_GEMS::WARNED.clear
  end

  def teardown
    Gem::BUNDLED_GEMS::WARNED.clear
  end

  def test_warning
    warning_info = Gem::BUNDLED_GEMS.warning?("csv", specs: {})
    assert warning_info
    Gem::BUNDLED_GEMS.build_message(warning_info)
    assert_nil Gem::BUNDLED_GEMS.warning?("csv", specs: {})
  end

  def test_no_warning_warning
    assert_nil Gem::BUNDLED_GEMS.warning?("some_gem", specs: {})
    assert_nil Gem::BUNDLED_GEMS.warning?("/path/to/some_gem.rb", specs: {})
  end

  def test_warning_libdir
    path = File.join(::RbConfig::CONFIG.fetch("rubylibdir"), "csv.rb")
    warning_info = Gem::BUNDLED_GEMS.warning?(path, specs: {})
    assert warning_info
    Gem::BUNDLED_GEMS.build_message(warning_info)
    assert_nil Gem::BUNDLED_GEMS.warning?(path, specs: {})
  end

  def test_warning_archdir
    path = File.join(::RbConfig::CONFIG.fetch("rubyarchdir"), "syslog.so")
    warning_info = Gem::BUNDLED_GEMS.warning?(path, specs: {})
    assert warning_info
    Gem::BUNDLED_GEMS.build_message(warning_info)
    assert_nil Gem::BUNDLED_GEMS.warning?(path, specs: {})
  end
end
