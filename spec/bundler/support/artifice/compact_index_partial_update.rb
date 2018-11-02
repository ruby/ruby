# frozen_string_literal: true

require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

class CompactIndexPartialUpdate < CompactIndexAPI
  # Stub the server to never return 304s. This simulates the behaviour of
  # Fastly / Rubygems ignoring ETag headers.
  def not_modified?(_checksum)
    false
  end

  get "/versions" do
    cached_versions_path = File.join(
      Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions"
    )

    # Verify a cached copy of the versions file exists
    unless File.read(cached_versions_path).start_with?("created_at: ")
      raise("Cached versions file should be present and have content")
    end

    # Verify that a partial request is made, starting from the index of the
    # final byte of the cached file.
    unless env["HTTP_RANGE"] == "bytes=#{File.read(cached_versions_path).bytesize - 1}-"
      raise("Range header should be present, and start from the index of the final byte of the cache.")
    end

    etag_response do
      # Return the exact contents of the cache.
      File.read(cached_versions_path)
    end
  end
end

Artifice.activate_with(CompactIndexPartialUpdate)
