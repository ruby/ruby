# frozen_string_literal: true

require_relative "endpoint_fallback"

Artifice.deactivate

class EndpointTimeout < EndpointFallback
  SLEEP_TIMEOUT = 3

  get "/api/v1/dependencies" do
    sleep(SLEEP_TIMEOUT)
  end
end

Artifice.activate_with(EndpointTimeout)
