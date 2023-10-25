# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexForbidden < CompactIndexAPI
  get "/versions" do
    halt 403
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexForbidden)
