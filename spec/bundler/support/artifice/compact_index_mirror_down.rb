# frozen_string_literal: true

require_relative "helpers/compact_index"
require_relative "helpers/artifice"
require_relative "helpers/rack_request"

module Artifice
  module Net
    class HTTPMirrorDown < HTTP
      def connect
        raise SocketError if address == "gem.mirror"

        super
      end
    end

    HTTP.endpoint = CompactIndexAPI
  end

  replace_net_http(Net::HTTPMirrorDown)
end
