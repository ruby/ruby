# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointStrictBasicAuthentication < Endpoint
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end

    # Only accepts password == "password"
    unless env["HTTP_AUTHORIZATION"] == "Basic dXNlcjpwYXNz"
      halt 403, "Authentication failed"
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointStrictBasicAuthentication)
