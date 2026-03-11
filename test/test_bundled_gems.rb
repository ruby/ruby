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

  def test_no_warning_for_hyphenated_gem
    # When benchmark-ips gem is in specs, requiring "benchmark/ips" should not warn
    # about the benchmark gem (Bug #21828)
    assert_nil Gem::BUNDLED_GEMS.warning?("benchmark/ips", specs: {"benchmark-ips" => true})
  end

  def test_no_warning_for_subfeatures_of_hyphenated_gem
    # When benchmark-ips gem is in specs, requiring any "benchmark/*" subfeature
    # should not warn, since hyphenated gems may provide multiple files
    # (e.g., benchmark-ips provides benchmark/ips, benchmark/timing, benchmark/compare)
    assert_nil Gem::BUNDLED_GEMS.warning?("benchmark/timing", specs: {"benchmark-ips" => true})
    assert_nil Gem::BUNDLED_GEMS.warning?("benchmark/compare", specs: {"benchmark-ips" => true})
  end

  def test_warning_without_hyphenated_gem
    # When benchmark-ips is NOT in specs, requiring "benchmark/ips" should warn
    warning = Gem::BUNDLED_GEMS.warning?("benchmark/ips", specs: {})
    assert warning
    assert_match(/benchmark/, warning)
  end

  def test_no_warning_for_subfeature_found_outside_stdlib
    # When a subfeature like "benchmark/ips" is found on $LOAD_PATH
    # from a non-standard-library location (e.g., benchmark-ips gem's lib dir),
    # don't warn even if the gem is not in specs (Bug #21828)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "benchmark"))
      File.write(File.join(dir, "benchmark", "ips.rb"), "")
      $LOAD_PATH.unshift(dir)
      begin
        assert_nil Gem::BUNDLED_GEMS.warning?("benchmark/ips", specs: {})
      ensure
        $LOAD_PATH.shift
      end
    end
  end
end
