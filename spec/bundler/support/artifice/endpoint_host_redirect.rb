# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointHostRedirect < Endpoint
  get "/fetch/actual/gem/:id", :host_name => "localgemserver.test" do
    redirect "http://bundler.localgemserver.test#{request.path_info}"
  end

  get "/api/v1/dependencies" do
    status 404
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointHostRedirect)
