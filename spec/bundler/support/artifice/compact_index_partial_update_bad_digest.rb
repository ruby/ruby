# frozen_string_literal: true

require_relative "helpers/compact_index"

# The purpose of this Artifice is to test that an incremental response is invalidated
# and a second request is issued for the full content.
class CompactIndexPartialUpdateBadDigest < CompactIndexAPI
  def partial_update_bad_digest
    response_body = yield
    if request.env["HTTP_RANGE"]
      headers "Repr-Digest" => "sha-256=:#{Digest::SHA256.base64digest("wrong digest on ranged request")}:"
    else
      headers "Repr-Digest" => "sha-256=:#{Digest::SHA256.base64digest(response_body)}:"
    end
    headers "Surrogate-Control" => "max-age=2592000, stale-while-revalidate=60"
    content_type "text/plain"
    requested_range_for(response_body)
  end

  get "/versions" do
    partial_update_bad_digest do
      file = tmp("versions.list")
      FileUtils.rm_f(file)
      file = CompactIndex::VersionsFile.new(file.to_s)
      file.create(gems)
      file.contents([], :calculate_info_checksums => true)
    end
  end

  get "/info/:name" do
    partial_update_bad_digest do
      gem = gems.find {|g| g.name == params[:name] }
      CompactIndex.info(gem ? gem.versions : [])
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexPartialUpdateBadDigest)
