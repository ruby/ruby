# frozen_string_literal: true

require_relative "helper"
require "rubygems/compact_index_client"

class TestGemCompactIndexClient < Gem::TestCase
  class FakeResponse < Gem::Net::HTTPOK
    def initialize(body)
      super("1.1", "200", "OK")
      @fake_body = body
    end

    attr_reader :fake_body
    alias_method :body, :fake_body
  end

  class FakeFetcher
    FILES = {
      "names" => "---\na\nb\n",
      "versions" => "created_at: 2026-06-10T00:00:00Z\n---\n" \
                    "a 1.0.0,1.1.0 #{Digest::MD5.hexdigest("---\n1.0.0 |checksum:c1\n1.1.0 |checksum:c2,created_at:2026-06-05T10:30:45Z\n")}\n" \
                    "b 1.0.0-java #{Digest::MD5.hexdigest("---\n1.0.0-java |checksum:c3\n")}\n",
      "info/a" => "---\n1.0.0 |checksum:c1\n1.1.0 |checksum:c2,created_at:2026-06-05T10:30:45Z\n",
      "info/b" => "---\n1.0.0-java |checksum:c3\n",
    }.freeze

    attr_reader :requests

    def initialize
      @requests = []
    end

    def call(path, headers)
      @requests << path
      FakeResponse.new(FILES.fetch(path))
    end
  end

  def setup
    super

    @fetcher = FakeFetcher.new
    @client = Gem::CompactIndexClient.new(File.join(@tempdir, "compact_index"), @fetcher)
  end

  def test_names
    assert_equal %w[a b], @client.names
  end

  def test_versions
    versions = @client.versions

    assert_equal [["a", "1.0.0"], ["a", "1.1.0"]], versions["a"]
    assert_equal [["b", "1.0.0", "java"]], versions["b"]
  end

  def test_info_returns_parsed_info_arrays
    info = @client.info("a")

    assert_equal 2, info.size
    assert_equal "a", info.last[Gem::CompactIndexClient::INFO_NAME]
    assert_equal "1.1.0", info.last[Gem::CompactIndexClient::INFO_VERSION]
    assert_nil info.last[Gem::CompactIndexClient::INFO_PLATFORM]
    assert_includes info.last[Gem::CompactIndexClient::INFO_REQS], ["created_at", ["2026-06-05T10:30:45Z"]]
  end

  def test_dependencies
    dependencies = @client.dependencies(%w[a b])

    assert_equal 2, dependencies.size
    assert_equal "b", dependencies.last.first[Gem::CompactIndexClient::INFO_NAME]
    assert_equal "java", dependencies.last.first[Gem::CompactIndexClient::INFO_PLATFORM]
  end

  def test_latest_version
    assert_equal Gem::Version.new("1.1.0"), @client.latest_version("a")
  end

  def test_available
    assert @client.available?
  end

  def test_not_available_without_data
    client = Gem::CompactIndexClient.new(File.join(@tempdir, "empty_index"))

    refute client.available?
  end

  def test_fetch_info_does_not_fetch_versions_index
    info = @client.fetch_info("a")

    assert_equal %w[info/a], @fetcher.requests
    assert_equal "1.1.0", info.last[Gem::CompactIndexClient::INFO_VERSION]
    assert_includes info.last[Gem::CompactIndexClient::INFO_REQS], ["created_at", ["2026-06-05T10:30:45Z"]]
  end

  def test_fetch_info_fetches_once_per_process
    @client.fetch_info("a")
    @client.fetch_info("a")

    assert_equal %w[info/a], @fetcher.requests
  end

  def test_reset_refetches_versions
    @client.versions
    @client.reset!
    @client.versions

    assert_equal %w[versions versions], @fetcher.requests
  end

  def test_info_uses_local_cache_when_checksum_matches
    @client.versions # prime info checksums and write cache
    @client.info("a")

    requests_before = @fetcher.requests.dup
    fresh = Gem::CompactIndexClient.new(File.join(@tempdir, "compact_index"), @fetcher)
    fresh.versions
    fresh.info("a")

    assert_equal requests_before + ["versions"], @fetcher.requests
  end
end
