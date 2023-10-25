# frozen_string_literal: false
# = uri/wss.rb
#
# Author:: Matt Muller <mamuller@amazon.com>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See Bundler::URI for general documentation
#

require_relative 'ws'

module Bundler::URI

  # The default port for WSS URIs is 443, and the scheme is 'wss:' rather
  # than 'ws:'. Other than that, WSS URIs are identical to WS URIs;
  # see Bundler::URI::WS.
  class WSS < WS
    # A Default port of 443 for Bundler::URI::WSS
    DEFAULT_PORT = 443
  end

  register_scheme 'WSS', WSS
end
