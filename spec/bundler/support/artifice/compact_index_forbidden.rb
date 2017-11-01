# frozen_string_literal: true

require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

class CompactIndexForbidden < CompactIndexAPI
  get "/versions" do
    halt 403
  end
end

Artifice.activate_with(CompactIndexForbidden)
