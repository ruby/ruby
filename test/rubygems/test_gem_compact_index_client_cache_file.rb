# frozen_string_literal: true

require_relative "helper"
require "pathname" unless defined?(Pathname)
require "rubygems/compact_index_client"

class TestGemCompactIndexClientCacheFile < Gem::TestCase
  CacheFile = Gem::CompactIndexClient::CacheFile

  def setup
    super

    @path = Pathname(@tempdir).join("versions")
  end

  def sha256(data)
    { "sha-256" => Digest::SHA256.base64digest(data) }
  end

  def test_write_creates_file
    CacheFile.write(@path, "created_at: 2026-06-10\n---\nrake 13.0.0\n")

    assert_equal "created_at: 2026-06-10\n---\nrake 13.0.0\n", @path.read
  end

  def test_write_replaces_original_file
    @path.binwrite "old"

    CacheFile.write(@path, "new")

    assert_equal "new", @path.read
  end

  def test_write_removes_temp_file
    CacheFile.write(@path, "data")

    assert_empty Dir.glob("#{@path}.*.tmp")
  end

  def test_write_nil_data_does_nothing
    CacheFile.write(@path, nil)

    refute @path.exist?
  end

  def test_write_with_matching_digests
    CacheFile.write(@path, "data", sha256("data"))

    assert_equal "data", @path.read
  end

  def test_write_with_mismatched_digests
    @path.binwrite "old"

    assert_raise CacheFile::DigestMismatchError do
      CacheFile.write(@path, "data", sha256("other data"))
    end

    assert_equal "old", @path.read
  end

  def test_append_without_digests_returns_false
    @path.binwrite "abc"

    appended = nil
    CacheFile.new(@path) {|file| appended = file.append("def") }

    refute appended
    assert_equal "abc", @path.read
  end

  def test_append_with_matching_digests
    @path.binwrite "abc"

    appended = nil
    CacheFile.copy(@path) do |file|
      file.digests = sha256("abcdef")
      appended = file.append("def")
    end

    assert appended
    assert_equal "abcdef", @path.read
  end

  def test_append_with_mismatched_digests_keeps_original
    @path.binwrite "abc"

    appended = nil
    CacheFile.copy(@path) do |file|
      file.digests = sha256("abcxyz")
      appended = file.append("def")
    end

    refute appended
    assert_equal "abc", @path.read
  end

  def test_close_removes_temp_file
    file = CacheFile.new(@path)
    file.open {|f| f.write "data" }
    file.close

    assert_empty Dir.glob("#{@path}.*.tmp")
    refute @path.exist?
  end

  def test_open_after_close_raises
    file = CacheFile.new(@path)
    file.close

    assert_raise CacheFile::ClosedError do
      file.open {|f| f.write "data" }
    end
  end

  def test_commit_after_close_raises
    file = CacheFile.new(@path)
    file.close

    assert_raise CacheFile::ClosedError do
      file.commit
    end
  end

  def test_write_preserves_permissions
    @path.binwrite "old"
    @path.chmod 0o400

    CacheFile.write(@path, "new")

    assert_equal "new", @path.binread
    assert_equal 0, @path.stat.mode & 0o200, "expected CacheFile.write to preserve the original read-only permission"
  end
end
