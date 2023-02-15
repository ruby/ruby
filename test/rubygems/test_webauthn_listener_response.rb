# frozen_string_literal: true

require_relative "helper"
require "rubygems/webauthn_listener/response/response_ok"
require "rubygems/webauthn_listener/response/response_no_content"
require "rubygems/webauthn_listener/response/response_bad_request"
require "rubygems/webauthn_listener/response/response_not_found"
require "rubygems/webauthn_listener/response/response_method_not_allowed"

class WebauthnListenerResponseTest < Gem::TestCase
  class MockResponse < Gem::WebauthnListener::Response
    def payload
      "hello world"
    end
  end

  def setup
    super
    @host = "rubygems.example"
  end

  def test_ok_response_payload
    payload = Gem::WebauthnListener::ResponseOk.new(@host).payload

    expected_payload = <<~RESPONSE
      HTTP/1.1 200 OK
      Connection: close
      Access-Control-Allow-Origin: rubygems.example
      Access-Control-Allow-Methods: POST
      Access-Control-Allow-Headers: Content-Type, Authorization, x-csrf-token
      Content-Type: text/plain
      Content-Length: 7

      success
    RESPONSE

    assert_equal expected_payload, payload
  end

  def test_no_payload_response_payload
    payload = Gem::WebauthnListener::ResponseNoContent.new(@host).payload

    expected_payload = <<~RESPONSE
      HTTP/1.1 204 No Content
      Connection: close
      Access-Control-Allow-Origin: rubygems.example
      Access-Control-Allow-Methods: POST
      Access-Control-Allow-Headers: Content-Type, Authorization, x-csrf-token
    RESPONSE

    assert_equal expected_payload, payload
  end

  def test_method_not_allowed_response_payload
    payload = Gem::WebauthnListener::ResponseMethodNotAllowed.new(@host).payload

    expected_payload = <<~RESPONSE
      HTTP/1.1 405 Method Not Allowed
      Connection: close
      Allow: GET, OPTIONS
    RESPONSE

    assert_equal expected_payload, payload
  end

  def test_method_not_found_response_payload
    payload = Gem::WebauthnListener::ResponseNotFound.new(@host).payload

    expected_payload = <<~RESPONSE
      HTTP/1.1 404 Not Found
      Connection: close
    RESPONSE

    assert_equal expected_payload, payload
  end

  def test_bad_request_response_payload
    payload = Gem::WebauthnListener::ResponseBadRequest.new(@host).payload

    expected_payload = <<~RESPONSE
      HTTP/1.1 400 Bad Request
      Connection: close
      Content-Type: text/plain
      Content-Length: 22

      missing code parameter
    RESPONSE

    assert_equal expected_payload, payload
  end

  def test_send_response
    server = TCPServer.new "localhost", 5678
    thread = Thread.new do
      receive_socket = server.accept
      Thread.current[:payload] = receive_socket.read
      receive_socket.close
    end

    send_socket = TCPSocket.new "localhost", 5678
    MockResponse.send(send_socket, @host)

    thread.join
    assert_equal "hello world", thread[:payload]
    assert_predicate send_socket, :closed?
  end
end
