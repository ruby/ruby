# frozen_string_literal: true

require_relative "endpoint"

Artifice.deactivate

class EndpointApiMissing < Endpoint
  get "/fetch/actual/gem/:id" do
    warn params[:id]
    if params[:id] == "rack-1.0.gemspec.rz"
      halt 404
    else
      File.binread("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
    end
  end
end

Artifice.activate_with(EndpointApiMissing)
