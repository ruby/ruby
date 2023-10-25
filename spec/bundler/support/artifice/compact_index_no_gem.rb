# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexNoGem < CompactIndexAPI
  get "/gems/:id" do
    halt 500
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexNoGem)
