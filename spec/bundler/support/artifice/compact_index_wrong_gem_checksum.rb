# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexWrongGemChecksum < CompactIndexAPI
  get "/info/:name" do
    etag_response do
      name = params[:name]
      gem = gems.find {|g| g.name == name }
      checksum = ENV.fetch("BUNDLER_SPEC_#{name.upcase}_CHECKSUM") { "ab" * 22 }
      versions = gem ? gem.versions : []
      versions.each {|v| v.checksum = checksum }
      CompactIndex.info(versions)
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexWrongGemChecksum)
