#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/remote_installer'

class MockFetcher
  def initialize(uri, proxy)
    @uri = uri
    @proxy = proxy
  end

  def size
    1000
  end
  
  def source_index
    if @uri =~ /non.existent.url/
      fail Gem::RemoteSourceException,
        "Error fetching remote gem cache: Mock Socket Exception"
    end
    result = {
      'foo-1.2.3' => Gem::Specification.new do |s|
        s.name = 'foo'
        s.version = "1.2.3"
        s.summary = "This is a cool package"
      end,
      'foo-tools-2.0.0' => Gem::Specification.new do |s|
        s.name = 'foo-tools'
        s.version = "2.0.0"
        s.summary = "This is an even cooler package"
      end,
      'foo-2-2.0.0' => Gem::Specification.new do |s|
        s.name = 'foo-2'
        s.version = "2.0.0"
        s.summary = "This is the coolest package evar!~!"
      end,
    }
    result
  end

  def fetch_path(path)
  end

  def self.finish
  end
end

class TestGemRemoteInstaller < RubyGemTestCase

  def setup
    super

    util_setup_fake_fetcher

    util_setup_source_info_cache @gem1, @gem4

    @installer = Gem::RemoteInstaller.new
    @installer.instance_variable_set("@fetcher_class", MockFetcher)
  end

  def teardown
    FileUtils.rm "dest_file" rescue nil
  end

  def test_find_gem_to_install
    future_gem = quick_gem @gem1.name, '9.9.9' do |spec|
      spec.required_ruby_version = '> 999.999.999' # HACK
    end

    util_setup_source_info_cache @gem1, future_gem
    version = Gem::Version::Requirement.new "> 0.0.0"
    gems = @installer.find_gem_to_install(@gem1.name, version)

    assert_equal @gem1.full_name, gems.first.full_name
  end

  def test_source_index_hash
    source_hash = @installer.source_index_hash

    assert_equal 1, source_hash.size
    assert source_hash.has_key?('http://gems.example.com')
    assert_equal [@gem1, @gem4],
                 source_hash['http://gems.example.com'].search(@gem1.name)
  end

  def test_specs_n_sources_matching
    version = Gem::Version::Requirement.new "> 0.0.0"
    specs_n_sources = @installer.specs_n_sources_matching @gem1.name, version

    gems = specs_n_sources.map { |g,| g.full_name }

    assert_equal [@gem1.full_name], gems,
                 "Gems with longer names and higher versions must not match"
  end

end

# This test suite has a number of TODOs in the test cases.  The
# TestRemoteInstaller test suite is a reworking of this class from
# scratch.
class RemoteInstallerTest #< RubyGemTestCase # HACK disabled
  class RInst < Gem::RemoteInstaller
    include Test::Unit::Assertions

    attr_accessor :expected_destination_files
    attr_accessor :expected_bodies
    attr_accessor :caches
    attr_accessor :responses

    def source_index_hash
      @caches
    end

    def fetch(uri)
      @reponses ||= {}
      @responses[uri]
    end

    def write_gem_to_file(body, destination_file)
      expected_destination_file = expected_destination_files.pop
      expected_body = expected_bodies.pop
      assert_equal expected_body, body, "Unexpected body"
      assert_equal expected_destination_file, destination_file, "Unexpected destination file"
    end

    def new_installer(gem)
      return MockInstaller.new(gem)
    end
  end

  def setup
    Gem.clear_paths
    @remote_installer = Gem::RemoteInstaller.new
    @remote_installer.instance_eval { @fetcher_class = MockFetcher }
  end

  SAMPLE_SPEC = Gem::Specification.new do |s|
    s.name = 'foo'
    s.version = "1.2.3"
    s.platform = Gem::Platform::RUBY
    s.summary = "This is a cool package"
    s.files = []
  end
  SAMPLE_CACHE = { 'foo-1.2.3' => SAMPLE_SPEC }
  SAMPLE_CACHE_YAML = SAMPLE_CACHE.to_yaml

  FOO_GEM = '' # TODO
  CACHE_DIR = File.join(Gem.dir, 'cache')

  def test_install
    result = @remote_installer.install('foo')
    assert_equal [nil], result
  end

end

