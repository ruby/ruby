# frozen_string_literal: true

require_relative "helper"
require "pathname"
require "rubygems/compact_index_client"

class TestGemCompactIndexClientCache < Gem::TestCase
  class FakeResponse < Gem::Net::HTTPOK
    def initialize(body)
      super("1.1", "200", "OK")
      @fake_body = body
    end

    attr_reader :fake_body
    alias_method :body, :fake_body
  end

  class FakeFetcher
    attr_reader :requests

    def initialize(body)
      @body = body
      @requests = []
    end

    def call(path, headers)
      @requests << path
      FakeResponse.new(@body)
    end
  end

  def setup
    super

    @dir = Pathname(@tempdir).join("compact_index")
  end

  def test_initialize_creates_cache_directories
    Gem::CompactIndexClient::Cache.new(@dir)

    assert @dir.join("info").directory?
    assert @dir.join("info-special-characters").directory?
    assert @dir.join("info-etags").directory?
  end

  def test_reads_cached_files_without_fetcher
    cache = Gem::CompactIndexClient::Cache.new(@dir)
    @dir.join("versions").write "a 1.0.0\n"

    assert_equal "a 1.0.0\n", cache.versions
    assert_nil cache.names
  end

  def test_versions_fetches_once
    fetcher = FakeFetcher.new("a 1.0.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)

    assert_equal "a 1.0.0\n", cache.versions
    assert_equal "a 1.0.0\n", cache.versions
    assert_equal ["versions"], fetcher.requests
    assert_equal "a 1.0.0\n", @dir.join("versions").read
  end

  def test_reset_allows_fetching_again
    fetcher = FakeFetcher.new("a 1.0.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)

    cache.versions
    cache.reset!
    cache.versions

    assert_equal %w[versions versions], fetcher.requests
  end

  def test_info_skips_fetch_when_checksum_matches
    fetcher = FakeFetcher.new("a 1.0.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)
    @dir.join("info", "a").write "a 1.0.0\n"

    content = cache.info("a", Digest::MD5.hexdigest("a 1.0.0\n"))

    assert_equal "a 1.0.0\n", content
    assert_empty fetcher.requests
  end

  def test_info_fetches_when_checksum_differs
    fetcher = FakeFetcher.new("a 1.0.0\na 1.1.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)
    @dir.join("info", "a").write "a 1.0.0\n"

    content = cache.info("a", Digest::MD5.hexdigest("a 1.0.0\na 1.1.0\n"))

    assert_equal "a 1.0.0\na 1.1.0\n", content
    assert_equal ["info/a"], fetcher.requests
    assert_equal "a 1.0.0\na 1.1.0\n", @dir.join("info", "a").read
  end

  def test_info_without_checksum_reads_cached_file
    fetcher = FakeFetcher.new("a 1.0.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)
    @dir.join("info", "a").write "a 1.0.0\n"

    assert_equal "a 1.0.0\n", cache.info("a")
    assert_empty fetcher.requests
  end

  def test_info_with_special_characters_uses_hashed_path
    fetcher = FakeFetcher.new("1.0.0\n")
    cache = Gem::CompactIndexClient::Cache.new(@dir, fetcher)

    cache.info("Rails", "no-match")

    hashed = "Rails-#{Digest::MD5.hexdigest("Rails").downcase}"
    assert_equal "1.0.0\n", @dir.join("info-special-characters", hashed).read
    refute @dir.join("info", "Rails").exist?
  end
end
