# frozen_string_literal: true

require File.expand_path("../endpoint_extra", __FILE__)

Artifice.deactivate

class EndpointExtraMissing < EndpointExtra
  get "/extra/fetch/actual/gem/:id" do
    if params[:id] == "missing-1.0.gemspec.rz"
      halt 404
    else
      File.read("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
    end
  end
end

Artifice.activate_with(EndpointExtraMissing)
