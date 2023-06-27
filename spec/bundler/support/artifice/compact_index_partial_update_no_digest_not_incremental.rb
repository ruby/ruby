# frozen_string_literal: true

require_relative "helpers/compact_index"

# The purpose of this Artifice is to test that an incremental response  is ignored
# when the digest is not present to verify that the partial response is valid.
class CompactIndexPartialUpdateNoDigestNotIncremental < CompactIndexAPI
  def partial_update_no_digest
    response_body = yield
    headers "Surrogate-Control" => "max-age=2592000, stale-while-revalidate=60"
    content_type "text/plain"
    requested_range_for(response_body)
  end

  get "/versions" do
    partial_update_no_digest do
      file = tmp("versions.list")
      FileUtils.rm_f(file)
      file = CompactIndex::VersionsFile.new(file.to_s)
      file.create(gems)
      lines = file.contents([], :calculate_info_checksums => true).split("\n")
      name, versions, checksum = lines.last.split(" ")

      # shuffle versions so new versions are not appended to the end
      [*lines[0..-2], [name, versions.split(",").reverse.join(","), checksum].join(" ")].join("\n")
    end
  end

  get "/info/:name" do
    partial_update_no_digest do
      gem = gems.find {|g| g.name == params[:name] }
      lines = CompactIndex.info(gem ? gem.versions : []).split("\n")

      # shuffle versions so new versions are not appended to the end
      [lines.first, lines.last, *lines[1..-2]].join("\n")
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexPartialUpdateNoDigestNotIncremental)
