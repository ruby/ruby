# frozen_string_literal: true

require_relative "endpoint_fallback"

Artifice.deactivate

class EndpointMarshalFail < EndpointFallback
  get "/api/v1/dependencies" do
    "f0283y01hasf"
  end
end

Artifice.activate_with(EndpointMarshalFail)
