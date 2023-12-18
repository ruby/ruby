# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexChecksumMismatch < CompactIndexAPI
  get "/versions" do
    headers "Repr-Digest" => "sha-256=:ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=:"
    headers "Surrogate-Control" => "max-age=2592000, stale-while-revalidate=60"
    content_type "text/plain"
    body "content does not match the checksum"
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexChecksumMismatch)
