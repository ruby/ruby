# frozen_string_literal: true

##
# The WebauthnListener Response class is used by the WebauthnListener to print
# the specified response to the Gem host using the provided socket. It also closes
# the socket after printing the response.
#
# Types of response classes:
#   - ResponseOk
#   - ResponseNoContent
#   - ResponseBadRequest
#   - ResponseNotFound
#   - ResponseMethodNotAllowed
#
# Example:
#   socket = TCPSocket.new(host, port)
#   Gem::WebauthnListener::ResponseOk.send(socket, host)
#

class Gem::WebauthnListener
  class Response
    attr_reader :host

    def initialize(host)
      @host = host
    end

    def self.send(socket, host)
      socket.print new(host).payload
      socket.close
    end

    def payload
      status_line_and_connection + access_control_headers + content
    end

    private

    def status_line_and_connection
      <<~RESPONSE
        HTTP/1.1 #{status}
        Connection: close
      RESPONSE
    end

    def access_control_headers
      return "" unless add_access_control_headers?
      <<~RESPONSE
        Access-Control-Allow-Origin: #{host}
        Access-Control-Allow-Methods: POST
        Access-Control-Allow-Headers: Content-Type, Authorization, x-csrf-token
      RESPONSE
    end

    def content
      return "" unless body
      <<~RESPONSE
        Content-Type: text/plain
        Content-Length: #{body.bytesize}

        #{body}
      RESPONSE
    end

    def status
      raise NotImplementedError
    end

    def add_access_control_headers?
      false
    end

    def body; end
  end
end
