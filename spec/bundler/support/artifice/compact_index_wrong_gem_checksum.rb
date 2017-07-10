# frozen_string_literal: true
require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

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

Artifice.activate_with(CompactIndexWrongGemChecksum)
