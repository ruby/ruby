# frozen_string_literal: true

require_relative "endpoint_fallback"

class EndpointMarshalFail < EndpointFallback
  get "/api/v1/dependencies" do
    "f0283y01hasf"
  end
end
