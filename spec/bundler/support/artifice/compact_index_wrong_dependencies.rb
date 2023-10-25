# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexWrongDependencies < CompactIndexAPI
  get "/info/:name" do
    etag_response do
      gem = gems.find {|g| g.name == params[:name] }
      gem.versions.each {|gv| gv.dependencies.clear } if gem
      CompactIndex.info(gem ? gem.versions : [])
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexWrongDependencies)
