# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointBasicAuthentication < Endpoint
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointBasicAuthentication)
