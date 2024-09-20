# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexRangeIgnored < CompactIndexAPI
  # Stub the server to not return 304 so that we don't bypass all the logic
  def not_modified?(_checksum)
    false
  end

  get "/versions" do
    cached_versions_path = File.join(
      Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions"
    )

    # Verify a cached copy of the versions file exists
    unless File.binread(cached_versions_path).size > 0
      raise("Cached versions file should be present and have content")
    end

    # Verify that a partial request is made, starting from the index of the
    # final byte of the cached file.
    unless env.delete("HTTP_RANGE")
      raise("Expected client to write the full response on the first try")
    end

    etag_response do
      file = tmp("versions.list")
      FileUtils.rm_f(file)
      file = CompactIndex::VersionsFile.new(file.to_s)
      file.create(gems)
      file.contents
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexRangeIgnored)
