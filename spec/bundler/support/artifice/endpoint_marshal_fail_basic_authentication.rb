# frozen_string_literal: true

require_relative "helpers/endpoint_marshal_fail"

class EndpointMarshalFailBasicAuthentication < EndpointMarshalFail
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(EndpointMarshalFailBasicAuthentication)
