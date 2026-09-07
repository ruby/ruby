# frozen_string_literal: true

require "bundler/compact_index_client"
require "bundler/compact_index_client/cache_file"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient::CacheFile do
  let(:path) { Pathname.new(Dir.mktmpdir("localpath")).join("versions") }

  def sha256(data)
    { "sha-256" => Digest::SHA256.base64digest(data) }
  end

  it "appends in binary mode so line endings are preserved" do
    path.binwrite "created_at: 2026-06-10\n---\n"

    appended = nil
    described_class.copy(path) do |file|
      file.digests = sha256("created_at: 2026-06-10\n---\nrake 13.0.0\n")
      appended = file.append("rake 13.0.0\n")
    end

    expect(appended).to be_truthy
    # On Windows a text-mode append rewrites the appended LF as CRLF while the
    # digest is computed over the pre-write bytes, so verify passes but the file
    # on disk is corrupted. Read raw bytes to catch any stray carriage return.
    expect(path.binread).not_to include("\r")
    expect(path.binread).to eq("created_at: 2026-06-10\n---\nrake 13.0.0\n")
  end
end
