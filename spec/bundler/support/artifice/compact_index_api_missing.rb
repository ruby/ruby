# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexApiMissing < CompactIndexAPI
  get "/fetch/actual/gem/:id" do
    halt 404
  end
end

Artifice.activate_with(CompactIndexApiMissing)
