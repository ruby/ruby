# frozen_string_literal: true

require_relative "helper"
require "rubygems/gemcutter_utilities/webauthn_poller"
require "rubygems/gemcutter_utilities"

class WebauthnPollerTest < Gem::TestCase
  def setup
    super

    @host = Gem.host
    @webauthn_url = "#{@host}/api/v1/webauthn_verification/odow34b93t6aPCdY"
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher
    @credentials = {
      email: "email@example.com",
      password: "password",
    }
  end

  def test_poll_thread_success
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "{\"status\":\"success\",\"code\":\"Uvh6T57tkWuUnWYo\"}",
      code: 200,
      msg: "OK"
    )

    thread = Gem::GemcutterUtilities::WebauthnPoller.poll_thread({}, @host, @webauthn_url, @credentials)
    thread.join

    assert_equal thread[:otp], "Uvh6T57tkWuUnWYo"
  end

  def test_poll_thread_webauthn_verification_error
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "HTTP Basic: Access denied.",
      code: 401,
      msg: "Unauthorized"
    )

    thread = Gem::GemcutterUtilities::WebauthnPoller.poll_thread({}, @host, @webauthn_url, @credentials)
    thread.join

    assert_equal thread[:error].message, "Security device verification failed: Unauthorized"
  end

  def test_poll_thread_timeout_error
    raise_error = ->(*_args) { raise Gem::Timeout::Error, "execution expired" }
    Gem::Timeout.stub(:timeout, raise_error) do
      thread = Gem::GemcutterUtilities::WebauthnPoller.poll_thread({}, @host, @webauthn_url, @credentials)
      thread.join
      assert_equal thread[:error].message, "execution expired"
    end
  end

  def test_poll_for_otp_success
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "{\"status\":\"success\",\"code\":\"Uvh6T57tkWuUnWYo\"}",
      code: 200,
      msg: "OK"
    )

    otp = Gem::GemcutterUtilities::WebauthnPoller.new({}, @host).poll_for_otp(@webauthn_url, @credentials)

    assert_equal otp, "Uvh6T57tkWuUnWYo"
  end

  def test_poll_for_otp_pending_sleeps
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "{\"status\":\"pending\",\"message\":\"Security device authentication is still pending.\"}",
      code: 200,
      msg: "OK"
    )

    assert_raise Gem::Timeout::Error do
      Gem::Timeout.timeout(0.1) do
        Gem::GemcutterUtilities::WebauthnPoller.new({}, @host).poll_for_otp(@webauthn_url, @credentials)
      end
    end
  end

  def test_poll_for_otp_not_http_success
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "HTTP Basic: Access denied.",
      code: 401,
      msg: "Unauthorized"
    )

    error = assert_raise Gem::WebauthnVerificationError do
      Gem::GemcutterUtilities::WebauthnPoller.new({}, @host).poll_for_otp(@webauthn_url, @credentials)
    end

    assert_equal error.message, "Security device verification failed: Unauthorized"
  end

  def test_poll_for_otp_invalid_format
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "{}",
      code: 200,
      msg: "OK"
    )

    error = assert_raise Gem::WebauthnVerificationError do
      Gem::GemcutterUtilities::WebauthnPoller.new({}, @host).poll_for_otp(@webauthn_url, @credentials)
    end

    assert_equal error.message, "Security device verification failed: Invalid response from server"
  end

  def test_poll_for_otp_invalid_status
    @fetcher.data["#{@webauthn_url}/status.json"] = Gem::HTTPResponseFactory.create(
      body: "{\"status\":\"expired\",\"message\":\"The token in the link you used has either expired or been used already.\"}",
      code: 200,
      msg: "OK"
    )

    error = assert_raise Gem::WebauthnVerificationError do
      Gem::GemcutterUtilities::WebauthnPoller.new({}, @host).poll_for_otp(@webauthn_url, @credentials)
    end

    assert_equal error.message,
      "Security device verification failed: The token in the link you used has either expired or been used already."
  end
end
