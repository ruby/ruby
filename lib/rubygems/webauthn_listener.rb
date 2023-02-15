# frozen_string_literal: true

require_relative "webauthn_listener/response/response_ok"
require_relative "webauthn_listener/response/response_no_content"
require_relative "webauthn_listener/response/response_bad_request"
require_relative "webauthn_listener/response/response_not_found"
require_relative "webauthn_listener/response/response_method_not_allowed"

##
# The WebauthnListener class retrieves an OTP after a user successfully WebAuthns with the Gem host.
# An instance opens a socket using the TCPServer instance given and listens for a request from the Gem host.
# The request should be a GET request to the root path and contains the OTP code in the form
# of a query parameter `code`. The listener will return the code which will be used as the OTP for
# API requests.
#
# Types of responses sent by the listener after receiving a request:
#   - 200 OK: OTP code was successfully retrieved
#   - 204 No Content: If the request was an OPTIONS request
#   - 400 Bad Request: If the request did not contain a query parameter `code`
#   - 404 Not Found: The request was not to the root path
#   - 405 Method Not Allowed: OTP code was not retrieved because the request was not a GET/OPTIONS request
#
# Example usage:
#
#   server = TCPServer.new(0)
#   otp = Gem::WebauthnListener.wait_for_otp_code("https://rubygems.example", server)
#

class Gem::WebauthnListener
  attr_reader :host

  def initialize(host)
    @host = host
  end

  def self.wait_for_otp_code(host, server)
    new(host).fetch_otp_from_connection(server)
  end

  def fetch_otp_from_connection(server)
    loop do
      socket = server.accept
      request_line = socket.gets

      method, req_uri, _protocol = request_line.split(" ")
      req_uri = URI.parse(req_uri)

      unless root_path?(req_uri)
        ResponseNotFound.send(socket, host)
        raise Gem::WebauthnVerificationError, "Page at #{req_uri.path} not found."
      end

      case method.upcase
      when "OPTIONS"
        ResponseNoContent.send(socket, host)
        next # will be GET
      when "GET"
        if otp = parse_otp_from_uri(req_uri)
          ResponseOk.send(socket, host)
          return otp
        end
        ResponseBadRequest.send(socket, host)
        raise Gem::WebauthnVerificationError, "Did not receive OTP from #{host}."
      else
        ResponseMethodNotAllowed.send(socket, host)
        raise Gem::WebauthnVerificationError, "Invalid HTTP method #{method.upcase} received."
      end
    end
  end

  private

  def root_path?(uri)
    uri.path == "/"
  end

  def parse_otp_from_uri(uri)
    require "cgi"

    return if uri.query.nil?
    CGI.parse(uri.query).dig("code", 0)
  end
end
