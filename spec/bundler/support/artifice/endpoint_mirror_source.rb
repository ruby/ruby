# frozen_string_literal: true

require_relative "endpoint"

class EndpointMirrorSource < Endpoint
  get "/gems/:id" do
    if request.env["HTTP_X_GEMFILE_SOURCE"] == "https://server.example.org/"
      File.read("#{gem_repo1}/gems/#{params[:id]}")
    else
      halt 500
    end
  end
end

Artifice.activate_with(EndpointMirrorSource)
