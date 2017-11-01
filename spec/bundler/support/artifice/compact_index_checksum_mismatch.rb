# frozen_string_literal: true

require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

class CompactIndexChecksumMismatch < CompactIndexAPI
  get "/versions" do
    headers "ETag" => quote("123")
    headers "Surrogate-Control" => "max-age=2592000, stale-while-revalidate=60"
    content_type "text/plain"
    body ""
  end
end

Artifice.activate_with(CompactIndexChecksumMismatch)
