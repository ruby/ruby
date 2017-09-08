# frozen_string_literal: true
require File.expand_path("../endpoint_marshal_fail", __FILE__)

Artifice.deactivate

class EndpointMarshalFailBasicAuthentication < EndpointMarshalFail
  before do
    unless env["HTTP_AUTHORIZATION"]
      halt 401, "Authentication info not supplied"
    end
  end
end

Artifice.activate_with(EndpointMarshalFailBasicAuthentication)
