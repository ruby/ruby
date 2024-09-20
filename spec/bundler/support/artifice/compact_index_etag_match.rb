# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexEtagMatch < CompactIndexAPI
  get "/versions" do
    raise "ETag header should be present" unless env["HTTP_IF_NONE_MATCH"]
    headers "ETag" => env["HTTP_IF_NONE_MATCH"]
    status 304
    body ""
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexEtagMatch)
