# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexBasicAuthentication < CompactIndexAPI
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

Artifice.activate_with(CompactIndexBasicAuthentication)
