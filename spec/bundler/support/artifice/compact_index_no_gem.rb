# frozen_string_literal: true

require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

class CompactIndexNoGem < CompactIndexAPI
  get "/gems/:id" do
    halt 500
  end
end

Artifice.activate_with(CompactIndexNoGem)
