# frozen_string_literal: true

require File.expand_path("../endpoint", __FILE__)

Artifice.deactivate

class EndpointApiMissing < Endpoint
  get "/fetch/actual/gem/:id" do
    warn params[:id]
    if params[:id] == "rack-1.0.gemspec.rz"
      halt 404
    else
      File.read("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
    end
  end
end

Artifice.activate_with(EndpointApiMissing)
