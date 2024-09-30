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
    assert Gem::BUNDLED_GEMS.warning?("csv", specs: {})
    assert_nil Gem::BUNDLED_GEMS.warning?("csv", specs: {})
  end

  def test_no_warning_warning
    assert_nil Gem::BUNDLED_GEMS.warning?("some_gem", specs: {})
    assert_nil Gem::BUNDLED_GEMS.warning?("/path/to/some_gem.rb", specs: {})
  end

  def test_warning_libdir
    path = File.join(::RbConfig::CONFIG.fetch("rubylibdir"), "csv.rb")
    assert Gem::BUNDLED_GEMS.warning?(path, specs: {})
    assert_nil Gem::BUNDLED_GEMS.warning?(path, specs: {})
  end

  def test_warning_archdir
    path = File.join(::RbConfig::CONFIG.fetch("rubyarchdir"), "syslog.so")
    assert Gem::BUNDLED_GEMS.warning?(path, specs: {})
    assert_nil Gem::BUNDLED_GEMS.warning?(path, specs: {})
  end
end
