# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexForbidden < CompactIndexAPI
  get "/versions" do
    halt 403
  end
end

Artifice.activate_with(CompactIndexForbidden)
