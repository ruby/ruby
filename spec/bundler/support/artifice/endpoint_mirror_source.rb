# frozen_string_literal: true

require_relative "helpers/endpoint"

class EndpointMirrorSource < Endpoint
  get "/gems/:id" do
    if request.env["HTTP_X_GEMFILE_SOURCE"] == "https://server.example.org/"
      File.binread("#{gem_repo1}/gems/#{params[:id]}")
    else
      halt 500
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointMirrorSource)
