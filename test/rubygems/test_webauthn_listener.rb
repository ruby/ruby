# frozen_string_literal: true

require_relative "helper"
require "rubygems/gemcutter_utilities/webauthn_listener"
require "rubygems/gemcutter_utilities"

class WebauthnListenerTest < Gem::TestCase
  def setup
    super
    @server = TCPServer.new 0
    @port = @server.addr[1].to_s
  end

  def teardown
    @thread.kill.join if @thread
    @server&.close
    super
  end

  def test_listener_thread_retreives_otp_code
    thread = Gem::GemcutterUtilities::WebauthnListener.listener_thread(Gem.host, @server)
    Gem::MockBrowser.get Gem::URI("http://localhost:#{@port}?code=xyz")

    thread.join
    assert_equal "xyz", thread[:otp]
  end

  def test_listener_thread_sets_error
    thread = Gem::GemcutterUtilities::WebauthnListener.listener_thread(Gem.host, @server)
    Gem::MockBrowser.post Gem::URI("http://localhost:#{@port}?code=xyz")

    thread.join
    assert_equal "Security device verification failed: Invalid HTTP method POST received.", thread[:error].message
  end

  def test_wait_for_otp_code_get_follows_options
    wait_for_otp_code
    assert Gem::MockBrowser.options(Gem::URI("http://localhost:#{@port}?code=xyz")).is_a? Gem::Net::HTTPNoContent
    assert Gem::MockBrowser.get(Gem::URI("http://localhost:#{@port}?code=xyz")).is_a? Gem::Net::HTTPOK
  end

  def test_wait_for_otp_code_options_request
    wait_for_otp_code
    response = Gem::MockBrowser.options Gem::URI("http://localhost:#{@port}?code=xyz")

    assert response.is_a? Gem::Net::HTTPNoContent
    assert_equal Gem.host, response["access-control-allow-origin"]
    assert_equal "POST", response["access-control-allow-methods"]
    assert_equal "Content-Type, Authorization, x-csrf-token", response["access-control-allow-headers"]
    assert_equal "close", response["Connection"]
  end

  def test_wait_for_otp_code_get_request
    wait_for_otp_code
    response = Gem::MockBrowser.get Gem::URI("http://localhost:#{@port}?code=xyz")

    assert response.is_a? Gem::Net::HTTPOK
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
    assert_equal "7", response["Content-Length"]
    assert_equal Gem.host, response["access-control-allow-origin"]
    assert_equal "POST", response["access-control-allow-methods"]
    assert_equal "Content-Type, Authorization, x-csrf-token", response["access-control-allow-headers"]
    assert_equal "close", response["Connection"]
    assert_equal "success", response.body

    @thread.join
    assert_equal "xyz", @thread[:otp]
  end

  def test_wait_for_otp_code_invalid_post_req_method
    wait_for_otp_code_expect_error_with_message("Security device verification failed: Invalid HTTP method POST received.")
    response = Gem::MockBrowser.post Gem::URI("http://localhost:#{@port}?code=xyz")

    assert response
    assert response.is_a? Gem::Net::HTTPMethodNotAllowed
    assert_equal "GET, OPTIONS", response["allow"]
    assert_equal "close", response["Connection"]

    @thread.join
    assert_nil @thread[:otp]
  end

  def test_wait_for_otp_code_incorrect_path
    wait_for_otp_code_expect_error_with_message("Security device verification failed: Page at /path not found.")
    response = Gem::MockBrowser.post Gem::URI("http://localhost:#{@port}/path?code=xyz")

    assert response.is_a? Gem::Net::HTTPNotFound
    assert_equal "close", response["Connection"]

    @thread.join
    assert_nil @thread[:otp]
  end

  def test_wait_for_otp_code_no_params_response
    wait_for_otp_code_expect_error_with_message("Security device verification failed: Did not receive OTP from https://rubygems.org.")
    response = Gem::MockBrowser.get Gem::URI("http://localhost:#{@port}")

    assert response.is_a? Gem::Net::HTTPBadRequest
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
    assert_equal "22", response["Content-Length"]
    assert_equal "close", response["Connection"]
    assert_equal "missing code parameter", response.body

    @thread.join
    assert_nil @thread[:otp]
  end

  def test_wait_for_otp_code_incorrect_params
    wait_for_otp_code_expect_error_with_message("Security device verification failed: Did not receive OTP from https://rubygems.org.")
    response = Gem::MockBrowser.get Gem::URI("http://localhost:#{@port}?param=xyz")

    assert response.is_a? Gem::Net::HTTPBadRequest
    assert_equal "text/plain; charset=utf-8", response["Content-Type"]
    assert_equal "22", response["Content-Length"]
    assert_equal "close", response["Connection"]
    assert_equal "missing code parameter", response.body

    @thread.join
    assert_nil @thread[:otp]
  end

  private

  def wait_for_otp_code
    @thread = Thread.new do
      Thread.current[:otp] = Gem::GemcutterUtilities::WebauthnListener.new(Gem.host).wait_for_otp_code(@server)
    end
    @thread.abort_on_exception = true
    @thread.report_on_exception = false
  end

  def wait_for_otp_code_expect_error_with_message(message)
    @thread = Thread.new do
      error = assert_raise Gem::WebauthnVerificationError do
        Thread.current[:otp] = Gem::GemcutterUtilities::WebauthnListener.new(Gem.host).wait_for_otp_code(@server)
      end

      assert_equal message, error.message
    end
    @thread.abort_on_exception = true
    @thread.report_on_exception = false
  end
end
