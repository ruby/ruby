# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexConcurrentDownload < CompactIndexAPI
  get "/versions" do
    versions = File.join(Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions")

    # Verify the original content hasn't been deleted, e.g. on a retry
    data = File.binread(versions)
    data == "created_at" || raise("Original file should be present with expected content")

    # Verify this is only requested once for a partial download
    env["HTTP_RANGE"] == "bytes=#{data.bytesize - 1}-" || raise("Missing Range header for expected partial download")

    # Overwrite the file in parallel, which should be then overwritten
    # after a successful download to prevent corruption
    File.open(versions, "w") {|f| f.puts "another process" }

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

Artifice.activate_with(CompactIndexConcurrentDownload)
