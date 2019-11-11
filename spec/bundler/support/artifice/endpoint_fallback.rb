# frozen_string_literal: true

require_relative "endpoint"

Artifice.deactivate

class EndpointFallback < Endpoint
  DEPENDENCY_LIMIT = 60

  get "/api/v1/dependencies" do
    if params[:gems] && params[:gems].size <= DEPENDENCY_LIMIT
      Marshal.dump(dependencies_for(params[:gems]))
    else
      halt 413, "Too many gems to resolve, please request less than #{DEPENDENCY_LIMIT} gems"
    end
  end
end

Artifice.activate_with(EndpointFallback)
