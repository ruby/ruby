# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexNoGem < CompactIndexAPI
  get "/gems/:id" do
    halt 500
  end
end

Artifice.activate_with(CompactIndexNoGem)
