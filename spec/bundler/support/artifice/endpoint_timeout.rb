# frozen_string_literal: true

require_relative "helpers/endpoint_fallback"

class EndpointTimeout < EndpointFallback
  SLEEP_TIMEOUT = 3

  get "/api/v1/dependencies" do
    sleep(SLEEP_TIMEOUT)
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointTimeout)
