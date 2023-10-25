# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexRangeNotSatisfiable < CompactIndexAPI
  get "/versions" do
    if env["HTTP_RANGE"]
      status 416
    else
      etag_response do
        file = tmp("versions.list")
        FileUtils.rm_f(file)
        file = CompactIndex::VersionsFile.new(file.to_s)
        file.create(gems)
        file.contents
      end
    end
  end

  get "/info/:name" do
    if env["HTTP_RANGE"]
      status 416
    else
      etag_response do
        gem = gems.find {|g| g.name == params[:name] }
        CompactIndex.info(gem ? gem.versions : [])
      end
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexRangeNotSatisfiable)
