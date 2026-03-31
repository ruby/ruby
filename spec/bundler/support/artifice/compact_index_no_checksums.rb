# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexNoChecksums < CompactIndexAPI
  get "/info/:name" do
    etag_response do
      gem = gems.find {|g| g.name == params[:name] }
      gem.versions.map(&:number).join("\n")
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexNoChecksums)
