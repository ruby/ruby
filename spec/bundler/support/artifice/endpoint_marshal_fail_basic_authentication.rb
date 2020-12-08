# frozen_string_literal: true

require_relative "endpoint_marshal_fail"

Artifice.deactivate

class EndpointMarshalFailBasicAuthentication < EndpointMarshalFail
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

Artifice.activate_with(EndpointMarshalFailBasicAuthentication)
