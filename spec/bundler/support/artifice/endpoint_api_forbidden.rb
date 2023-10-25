# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointApiForbidden < Endpoint
  get "/api/v1/dependencies" do
    halt 403
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointApiForbidden)
