# frozen_string_literal: true

require_relative "helper"
require "rubygems/compact_index_client"

##
# Exercises the util_setup_compact_index test helper against the real
# Gem::CompactIndexClient to ensure the stubbed endpoints speak the
# compact index protocol correctly.

class TestGemCompactIndexStub < Gem::TestCase
  def setup
    super

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    @a1 = util_spec "a", "1.0.0", "b" => ">= 1.0"
    @a2 = util_spec "a", "1.1.0"
    @b1 = util_spec "b", "1.0.0"
    @c1 = util_spec "c", "1.0.0" do |s|
      s.platform = "java"
      s.required_ruby_version = ">= 3.0"
    end
  end

  def client
    Gem::CompactIndexClient.new(
      File.join(@tempdir, "compact_index"),
      Gem::CompactIndexClient::HTTPFetcher.new(@gem_repo, @fetcher)
    )
  end

  def test_serves_names
    util_setup_compact_index @a1, @a2, @b1

    assert_equal %w[a b], client.names
  end

  def test_serves_versions_with_platforms
    util_setup_compact_index @a1, @a2, @c1

    versions = client.versions

    assert_equal [["a", "1.0.0"], ["a", "1.1.0"]], versions["a"]
    assert_equal [["c", "1.0.0", "java"]], versions["c"]
  end

  def test_serves_info_with_dependencies_and_requirements
    util_setup_compact_index @a1, @a2, @b1, @c1

    info = client.info("a")

    assert_equal "1.0.0", info.first[Gem::CompactIndexClient::INFO_VERSION]
    assert_equal [["b", [">= 1.0"]]], info.first[Gem::CompactIndexClient::INFO_DEPS]

    ruby_req = client.info("c").first[Gem::CompactIndexClient::INFO_REQS].assoc("ruby")
    assert_equal ["ruby", [">= 3.0"]], ruby_req
  end

  def test_serves_created_at_metadata
    util_setup_compact_index @a1, @a2, created_at: { "a-1.1.0" => "2026-06-05T10:30:45Z" }

    info = client.info("a")

    assert_nil info.first[Gem::CompactIndexClient::INFO_REQS].assoc("created_at")
    assert_equal ["created_at", ["2026-06-05T10:30:45Z"]],
      info.last[Gem::CompactIndexClient::INFO_REQS].assoc("created_at")
  end

  def test_versions_checksums_match_info_files
    util_setup_compact_index @a1, @a2, @b1

    c = client
    c.versions
    c.info("a")

    # checksum from the versions index matches the cached info file, so a
    # fresh client only refetches the versions index
    fresh = client
    fresh.versions
    fresh.info("a")

    info_requests = @fetcher.requests.count {|req| req.path.end_with?("info/a") }
    assert_equal 1, info_requests
  end

  def test_repr_digest_verification_round_trip
    util_setup_compact_index @a1

    assert_equal [["a", "1.0.0"]], client.versions["a"]
    assert @tempdir && File.file?(File.join(@tempdir, "compact_index", "versions"))
  end
end
