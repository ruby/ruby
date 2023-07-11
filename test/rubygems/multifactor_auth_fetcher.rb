# frozen_string_literal: true

##
# A MultifactorAuthFetcher is a FakeFetcher that adds paths to data for requests related to
# multi-factor authentication.
#

require_relative "utilities"
require "json"

class Gem::MultifactorAuthFetcher < Gem::FakeFetcher
  attr_reader :host, :webauthn_url

  # GET /api/v1/webauthn_verification defaults to user does not have any security devices
  def initialize(host: nil)
    super()
    @host = host || Gem.host
    @path_token = "odow34b93t6aPCdY"
    @webauthn_url = "#{@host}/webauthn_verification/#{@path_token}"
    @data["#{@host}/api/v1/webauthn_verification"] = Gem::HTTPResponseFactory.create(
      body: "You don't have any security devices",
      code: 422,
      msg: "Unprocessable Entity"
    )
  end

  # given a url, return a response that requires multifactor authentication
  def respond_with_require_otp(url, success_body)
    response_fail = "You have enabled multifactor authentication"

    @data[url] = proc do
      @call_count ||= 0
      if (@call_count += 1).odd?
        Gem::HTTPResponseFactory.create(body: response_fail, code: 401, msg: "Unauthorized")
      else
        Gem::HTTPResponseFactory.create(body: success_body, code: 200, msg: "OK")
      end
    end
  end

  # GET /api/v1/webauthn_verification returns a webauthn url
  # GET /api/v1/webauthn_verification/:token/status.json (polling url) returns pending status
  def respond_with_webauthn_url
    @data["#{@host}/api/v1/webauthn_verification"] = Gem::HTTPResponseFactory.create(body: @webauthn_url, code: 200, msg: "OK")
    @data["#{@host}/api/v1/webauthn_verification/#{@path_token}/status.json"] = Gem::HTTPResponseFactory.create(
      body: { status: "pending", message: "Security device authentication is still pending." }.to_json,
      code: 200,
      msg: "OK"
    )
  end

  # GET /api/v1/webauthn_verification/:token/status.json returns success status with OTP code
  def respond_with_webauthn_polling(code)
    @data["#{@host}/api/v1/webauthn_verification/#{@path_token}/status.json"] = Gem::HTTPResponseFactory.create(
      body: { status: "success", code: code }.to_json,
      code: 200,
      msg: "OK"
    )
  end

  # GET /api/v1/webauthn_verification/:token/status.json returns expired status
  def respond_with_webauthn_polling_failure
    @data["#{@host}/api/v1/webauthn_verification/#{@path_token}/status.json"] = Gem::HTTPResponseFactory.create(
      body: {
        status: "expired",
        message: "The token in the link you used has either expired or been used already.",
      }.to_json,
      code: 200,
      msg: "OK"
    )
  end

  def webauthn_url_with_port(port)
    "#{@webauthn_url}?port=#{port}"
  end
end
