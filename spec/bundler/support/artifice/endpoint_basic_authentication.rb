# frozen_string_literal: true
require File.expand_path("../endpoint", __FILE__)

Artifice.deactivate

class EndpointBasicAuthentication < Endpoint
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

Artifice.activate_with(EndpointBasicAuthentication)
