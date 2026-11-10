# frozen_string_literal: true

# This module was initially borrowed from https://github.com/wycats/artifice
module Artifice
  # Activate Artifice with a particular Rack endpoint.
  #
  # Calling this method will replace the Gem::Net::HTTP system
  # with a replacement that routes all requests to the
  # Rack endpoint.
  #
  # @param [#call] endpoint A valid Rack endpoint
  def self.activate_with(endpoint)
    require_relative "rack_request"

    # Preserve the original on first activation only. Without ||=, a second
    # activate_with call saves the already-replaced Artifice::Net::HTTP, so
    # deactivate would fail to restore the real Gem::Net::HTTP.
    @original_net_http ||= ::Gem::Net::HTTP
    Net::HTTP.endpoint = endpoint
    replace_net_http(Artifice::Net::HTTP)
  end

  # Deactivate the Artifice replacement.
  def self.deactivate
    replace_net_http(@original_net_http) if @original_net_http
    @original_net_http = nil
  end

  def self.replace_net_http(value)
    ::Gem::Net.class_eval do
      remove_const(:HTTP)
      const_set(:HTTP, value)
    end
  end
end
