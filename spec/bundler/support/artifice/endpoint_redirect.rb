# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointRedirect < Endpoint
  get "/fetch/actual/gem/:id" do
    redirect "/fetch/actual/gem/#{params[:id]}"
  end

  get "/api/v1/dependencies" do
    status 404
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointRedirect)
