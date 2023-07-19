# frozen_string_literal: true

require_relative "helper"
require "rubygems/webauthn_listener/response"

class WebauthnListenerResponseTest < Gem::TestCase
  def setup
    super
    @host = "rubygems.example"
  end

  def test_ok_response_to_s
    to_s = Gem::WebauthnListener::OkResponse.new(@host).to_s

    expected_to_s = <<~RESPONSE
      HTTP/1.1 200 OK\r
      connection: close\r
      access-control-allow-origin: rubygems.example\r
      access-control-allow-methods: POST\r
      access-control-allow-headers: Content-Type, Authorization, x-csrf-token\r
      content-type: text/plain\r
      content-length: 7\r
      \r
      success
    RESPONSE

    assert_equal expected_to_s, to_s
  end

  def test_no_to_s_response_to_s
    to_s = Gem::WebauthnListener::NoContentResponse.new(@host).to_s

    expected_to_s = <<~RESPONSE
      HTTP/1.1 204 No Content\r
      connection: close\r
      access-control-allow-origin: rubygems.example\r
      access-control-allow-methods: POST\r
      access-control-allow-headers: Content-Type, Authorization, x-csrf-token\r
      \r
    RESPONSE

    assert_equal expected_to_s, to_s
  end

  def test_method_not_allowed_response_to_s
    to_s = Gem::WebauthnListener::MethodNotAllowedResponse.new(@host).to_s

    expected_to_s = <<~RESPONSE
      HTTP/1.1 405 Method Not Allowed\r
      connection: close\r
      access-control-allow-origin: rubygems.example\r
      access-control-allow-methods: POST\r
      access-control-allow-headers: Content-Type, Authorization, x-csrf-token\r
      allow: GET, OPTIONS\r
      \r
    RESPONSE

    assert_equal expected_to_s, to_s
  end

  def test_method_not_found_response_to_s
    to_s = Gem::WebauthnListener::NotFoundResponse.new(@host).to_s

    expected_to_s = <<~RESPONSE
      HTTP/1.1 404 Not Found\r
      connection: close\r
      access-control-allow-origin: rubygems.example\r
      access-control-allow-methods: POST\r
      access-control-allow-headers: Content-Type, Authorization, x-csrf-token\r
      \r
    RESPONSE

    assert_equal expected_to_s, to_s
  end

  def test_bad_request_response_to_s
    to_s = Gem::WebauthnListener::BadRequestResponse.new(@host).to_s

    expected_to_s = <<~RESPONSE
      HTTP/1.1 400 Bad Request\r
      connection: close\r
      access-control-allow-origin: rubygems.example\r
      access-control-allow-methods: POST\r
      access-control-allow-headers: Content-Type, Authorization, x-csrf-token\r
      content-type: text/plain\r
      content-length: 22\r
      \r
      missing code parameter
    RESPONSE

    assert_equal expected_to_s, to_s
  end
end
