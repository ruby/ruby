# frozen_string_literal: true

require_relative "helper"
require "rubygems/compact_index_client"

class TestGemCompactIndexClientParser < Gem::TestCase
  class FakeIndex
    attr_reader :info_requests

    def initialize(names: nil, versions: nil, info: {})
      @names = names
      @versions = versions
      @info = info
      @info_requests = {}
    end

    attr_reader :names, :versions

    def info(name, checksum)
      @info_requests[name] = checksum
      @info[name]
    end
  end

  def test_names_strips_header
    index = FakeIndex.new(names: "---\na\nb\n")
    parser = Gem::CompactIndexClient::Parser.new(index)

    assert_equal %w[a b], parser.names
  end

  def test_versions_parses_versions_and_platforms
    index = FakeIndex.new(versions: <<~VERSIONS)
      created_at: 2026-06-10T00:00:00Z
      ---
      a 1.0.0,1.1.0 aaa111
      b 1.0.0-java bbb222
    VERSIONS
    parser = Gem::CompactIndexClient::Parser.new(index)

    versions = parser.versions

    assert_equal [["a", "1.0.0"], ["a", "1.1.0"]], versions["a"]
    assert_equal [["b", "1.0.0", "java"]], versions["b"]
  end

  def test_versions_applies_deletions
    index = FakeIndex.new(versions: <<~VERSIONS)
      ---
      a 1.0.0,1.1.0 aaa111
      a -1.1.0 aaa222
    VERSIONS
    parser = Gem::CompactIndexClient::Parser.new(index)

    assert_equal [["a", "1.0.0"]], parser.versions["a"]
  end

  def test_info_passes_checksum_from_versions_index
    index = FakeIndex.new(versions: "---\na 1.0.0 aaa111\na 1.1.0 aaa222\n",
                          info: { "a" => "---\n1.0.0 |checksum:abc\n" })
    parser = Gem::CompactIndexClient::Parser.new(index)

    parser.info("a")

    assert_equal({ "a" => "aaa222" }, index.info_requests)
  end

  def test_info_parses_dependencies_and_requirements
    line = "1.2.0 b:>= 1.0&< 2.0,c:= 0.5" \
      "|checksum:abc123,ruby:>= 3.0,rubygems:>= 3.3.3,created_at:2026-06-05T10:30:45Z"
    index = FakeIndex.new(versions: "---\na 1.2.0 aaa111\n",
                          info: { "a" => "---\n#{line}\n" })
    parser = Gem::CompactIndexClient::Parser.new(index)

    info = parser.info("a")

    name, version, platform, dependencies, requirements = info.first
    assert_equal "a", name
    assert_equal "1.2.0", version
    assert_nil platform
    assert_equal [["b", [">= 1.0", "< 2.0"]], ["c", ["= 0.5"]]], dependencies
    assert_equal [["checksum", ["abc123"]], ["ruby", [">= 3.0"]],
                  ["rubygems", [">= 3.3.3"]], ["created_at", ["2026-06-05T10:30:45Z"]]], requirements
  end

  def test_info_parses_platform_version
    index = FakeIndex.new(versions: "---\na 1.0.0-java aaa111\n",
                          info: { "a" => "---\n1.0.0-java |checksum:abc\n" })
    parser = Gem::CompactIndexClient::Parser.new(index)

    _, version, platform, = parser.info("a").first

    assert_equal "1.0.0", version
    assert_equal "java", platform
  end

  def test_available_with_versions_data
    parser = Gem::CompactIndexClient::Parser.new(FakeIndex.new(versions: "---\na 1.0.0 aaa111\n"))

    assert parser.available?
  end

  def test_available_with_no_data
    parser = Gem::CompactIndexClient::Parser.new(FakeIndex.new)

    refute parser.available?
  end

  def test_skips_blank_lines_in_versions_index
    index = FakeIndex.new(versions: "---\na 1.0.0 aaa111\n\n",
                          info: { "a" => "1.0.0 |checksum:abc\n" })
    parser = Gem::CompactIndexClient::Parser.new(index)

    assert parser.available?
    assert_equal 1, parser.info("a").size
  end
end
