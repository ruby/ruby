# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexApiMissing < CompactIndexAPI
  get "/fetch/actual/gem/:id" do
    halt 404
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexApiMissing)
