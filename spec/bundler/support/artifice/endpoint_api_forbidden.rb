# frozen_string_literal: true

require File.expand_path("../endpoint", __FILE__)

Artifice.deactivate

class EndpointApiForbidden < Endpoint
  get "/api/v1/dependencies" do
    halt 403
  end
end

Artifice.activate_with(EndpointApiForbidden)
