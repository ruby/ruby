# frozen_string_literal: true

require_relative "helper"
require "rubygems"
require "rubygems/command"
require "rubygems/gemcutter_utilities"
require "rubygems/config_file"

class TestGemGemcutterUtilities < Gem::TestCase
  def setup
    super

    credential_setup
    @fetcher = SignInFetcher.new

    # below needed for random testing, class property
    Gem.configuration.disable_default_gem_server = nil

    ENV["RUBYGEMS_HOST"] = nil
    ENV["GEM_HOST_OTP_CODE"] = nil
    Gem.configuration.rubygems_api_key = nil

    @cmd = Gem::Command.new "", "summary"
    @cmd.extend Gem::GemcutterUtilities
  end

  def teardown
    ENV["RUBYGEMS_HOST"] = nil
    ENV["GEM_HOST_OTP_CODE"] = nil
    Gem.configuration.rubygems_api_key = nil

    credential_teardown

    super
  end

  def test_alternate_key_alternate_host
    keys = {
      :rubygems_api_key => "KEY",
      "http://rubygems.engineyard.com" => "EYKEY",
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end

    ENV["RUBYGEMS_HOST"] = "http://rubygems.engineyard.com"

    Gem.configuration.load_api_keys

    assert_equal "EYKEY", @cmd.api_key
  end

  def test_api_key
    keys = { :rubygems_api_key => "KEY" }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end

    Gem.configuration.load_api_keys

    assert_equal "KEY", @cmd.api_key
  end

  def test_api_key_override
    keys = { :rubygems_api_key => "KEY", :other => "OTHER" }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end

    Gem.configuration.load_api_keys

    @cmd.add_key_option
    @cmd.handle_options %w[--key other]

    assert_equal "OTHER", @cmd.api_key
  end

  def test_host
    assert_equal "https://rubygems.org", @cmd.host
  end

  def test_host_RUBYGEMS_HOST
    ENV["RUBYGEMS_HOST"] = "https://other.example"

    assert_equal "https://other.example", @cmd.host
  end

  def test_host_RUBYGEMS_HOST_empty
    ENV["RUBYGEMS_HOST"] = ""

    assert_equal "https://rubygems.org", @cmd.host
  end

  def test_sign_in
    util_sign_in

    assert_match(/Enter your RubyGems.org credentials./, @sign_in_ui.output)
    assert @fetcher.last_request["authorization"]
    assert_match(/Signed in./, @sign_in_ui.output)

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal @fetcher.api_key, credentials[:rubygems_api_key]
  end

  def test_sign_in_with_host
    @fetcher = SignInFetcher.new(host: "http://example.com")
    util_sign_in

    assert_match "Enter your http://example.com credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match(/Signed in./, @sign_in_ui.output)

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal @fetcher.api_key, credentials["http://example.com"]
  end

  def test_sign_in_with_host_nil
    @fetcher = SignInFetcher.new(host: nil)
    util_sign_in(args: [nil])

    assert_match "Enter your RubyGems.org credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match(/Signed in./, @sign_in_ui.output)

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal @fetcher.api_key, credentials[:rubygems_api_key]
  end

  def test_sign_in_with_host_ENV
    @fetcher = SignInFetcher.new(host: "http://example.com")
    util_sign_in

    assert_match "Enter your http://example.com credentials.",
                 @sign_in_ui.output
    assert @fetcher.last_request["authorization"]
    assert_match(/Signed in./, @sign_in_ui.output)

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal @fetcher.api_key, credentials["http://example.com"]
  end

  def test_sign_in_skips_with_existing_credentials
    Gem.configuration.rubygems_api_key = @fetcher.api_key

    util_sign_in

    assert_equal "", @sign_in_ui.output
  end

  def test_sign_in_skips_with_key_override
    Gem.configuration.api_keys[:KEY] = "other"
    @cmd.options[:key] = :KEY
    util_sign_in

    assert_equal "", @sign_in_ui.output
  end

  def test_sign_in_with_other_credentials_doesnt_overwrite_other_keys
    other_api_key = "f46dbb18bb6a9c97cdc61b5b85c186a17403cdcbf"

    config = Hash[:other_api_key, other_api_key]

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(config)
    end
    util_sign_in

    assert_match(/Enter your RubyGems.org credentials./, @sign_in_ui.output)
    assert_match(/Signed in./, @sign_in_ui.output)

    credentials = load_yaml_file Gem.configuration.credentials_path
    assert_equal @fetcher.api_key, credentials[:rubygems_api_key]
    assert_equal other_api_key, credentials[:other_api_key]
  end

  def test_sign_in_with_bad_credentials
    @fetcher.respond_with_forbidden_api_key_response
    assert_raise Gem::MockGemUi::TermError do
      util_sign_in
    end

    assert_match(/Enter your RubyGems.org credentials./, @sign_in_ui.output)
    assert_match(/Access Denied./, @sign_in_ui.output)
  end

  def test_signin_with_env_otp_code
    ENV["GEM_HOST_OTP_CODE"] = "111111"

    util_sign_in

    assert_match "Signed in with API key:", @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_correct_otp_code
    @fetcher.respond_with_require_otp
    util_sign_in(extra_input: "111111\n")

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @sign_in_ui.output
    assert_match "Code: ", @sign_in_ui.output
    assert_match "Signed in with API key:", @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_incorrect_otp_code
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."

    @fetcher.respond_with_unauthorized_api_key_response
    assert_raise Gem::MockGemUi::TermError do
      util_sign_in(extra_input: "111111\n")
    end

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @sign_in_ui.output
    assert_match "Code: ", @sign_in_ui.output
    assert_match response, @sign_in_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_webauthn_enabled
    webauthn_verification_url = "rubygems.org/api/v1/webauthn_verification/odow34b93t6aPCdY"
    port = 5678
    server = TCPServer.new(port)

    @fetcher.respond_with_require_otp
    @fetcher.respond_with_webauthn_url(webauthn_verification_url)
    TCPServer.stub(:new, server) do
      Gem::WebauthnListener.stub(:wait_for_otp_code, "Uvh6T57tkWuUnWYo") do
        util_sign_in
      end
    ensure
      server.close
    end

    url_with_port = "#{webauthn_verification_url}?port=#{port}"
    assert_match "You have enabled multi-factor authentication. Please visit #{url_with_port} to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, you can re-run the gem signin command with the `--otp [your_code]` option.", @sign_in_ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @sign_in_ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_webauthn_enabled_with_error
    webauthn_verification_url = "rubygems.org/api/v1/webauthn_verification/odow34b93t6aPCdY"
    port = 5678
    server = TCPServer.new(port)
    raise_error = ->(*_args) { raise Gem::WebauthnVerificationError, "Something went wrong" }

    @fetcher.respond_with_require_otp
    @fetcher.respond_with_webauthn_url(webauthn_verification_url)
    error = assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        Gem::WebauthnListener.stub(:wait_for_otp_code, raise_error) do
          util_sign_in
        end
      ensure
        server.close
      end
    end
    assert_equal 1, error.exit_code

    url_with_port = "#{webauthn_verification_url}?port=#{port}"
    assert_match "You have enabled multi-factor authentication. Please visit #{url_with_port} to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, you can re-run the gem signin command with the `--otp [your_code]` option.", @sign_in_ui.output
    assert_match "ERROR:  Security device verification failed: Something went wrong", @sign_in_ui.error
    refute_match "You are verified with a security device. You may close the browser window.", @sign_in_ui.output
    refute_match "Signed in with API key:", @sign_in_ui.output
  end

  def test_sign_in_with_webauthn_enabled_with_polling
    webauthn_verification_url = "rubygems.org/api/v1/webauthn_verification/odow34b93t6aPCdY"
    port = 5678
    server = TCPServer.new(port)
    @fetcher.respond_with_require_otp
    @fetcher.respond_with_webauthn_url(webauthn_verification_url)
    @fetcher.respond_with_webauthn_polling("Uvh6T57tkWuUnWYo")

    TCPServer.stub(:new, server) do
      util_sign_in
    ensure
      server.close
    end

    url_with_port = "#{webauthn_verification_url}?port=#{port}"
    assert_match "You have enabled multi-factor authentication. Please visit #{url_with_port} to authenticate " \
      "via security device. If you can't verify using WebAuthn but have OTP enabled, you can re-run the gem signin " \
      "command with the `--otp [your_code]` option.", @sign_in_ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @sign_in_ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
  end

  def test_sign_in_with_webauthn_enabled_with_polling_failure
    webauthn_verification_url = "rubygems.org/api/v1/webauthn_verification/odow34b93t6aPCdY"
    port = 5678
    server = TCPServer.new(port)
    @fetcher.respond_with_require_otp
    @fetcher.respond_with_webauthn_url(webauthn_verification_url)
    @fetcher.respond_with_webauthn_polling_failure

    assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        util_sign_in
      ensure
        server.close
      end
    end

    url_with_port = "#{webauthn_verification_url}?port=#{port}"
    assert_match "You have enabled multi-factor authentication. Please visit #{url_with_port} to authenticate " \
      "via security device. If you can't verify using WebAuthn but have OTP enabled, you can re-run the gem signin " \
      "command with the `--otp [your_code]` option.", @sign_in_ui.output
    assert_match "ERROR:  Security device verification failed: " \
      "The token in the link you used has either expired or been used already.", @sign_in_ui.error
  end

  def util_sign_in(args: [], extra_input: "")
    email             = "you@example.com"
    password          = "secret"

    ENV["RUBYGEMS_HOST"] = @fetcher.host
    Gem::RemoteFetcher.fetcher = @fetcher

    @sign_in_ui = Gem::MockGemUi.new("#{email}\n#{password}\n\n\n\n\n\n\n\n\n" + extra_input)

    use_ui @sign_in_ui do
      if args.length > 0
        @cmd.sign_in(*args)
      else
        @cmd.sign_in
      end
    end
  end

  def test_verify_api_key
    keys = { :other => "a5fdbb6ba150cbb83aad2bb2fede64cf040453903" }
    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    assert_equal "a5fdbb6ba150cbb83aad2bb2fede64cf040453903",
                 @cmd.verify_api_key(:other)
  end

  def test_verify_missing_api_key
    assert_raise Gem::MockGemUi::TermError do
      @cmd.verify_api_key :missing
    end
  end

  class SignInFetcher < Gem::FakeFetcher
    attr_reader :host, :api_key

    def initialize(host: nil)
      super()
      @host = host || Gem.host
      @api_key = "a5fdbb6ba150cbb83aad2bb2fede64cf040453903"
      @data["#{@host}/api/v1/api_key"] = Gem::HTTPResponseFactory.create(body: @api_key, code: 200, msg: "OK")
      @data["#{@host}/api/v1/profile/me.yaml"] = Gem::HTTPResponseFactory.create(body: "mfa: disabled\n", code: 200, msg: "OK")
      @data["#{@host}/api/v1/webauthn_verification"] = Gem::HTTPResponseFactory.create(
        body: "You don't have any security devices",
        code: 422,
        msg: "Unprocessable Entity"
      )
    end

    def respond_with_webauthn_url(url)
      require "json"
      @data["#{@host}/api/v1/webauthn_verification"] = Gem::HTTPResponseFactory.create(body: url, code: 200, msg: "OK")
      @data["#{@host}/api/v1/webauthn_verification/odow34b93t6aPCdY/status.json"] = Gem::HTTPResponseFactory.create(
        body: { status: "pending", message: "Security device authentication is still pending." }.to_json,
        code: 200,
        msg: "OK"
      )
    end

    def respond_with_webauthn_polling(code)
      require "json"
      @data["#{@host}/api/v1/webauthn_verification/odow34b93t6aPCdY/status.json"] = Gem::HTTPResponseFactory.create(
        body: { status: "success", code: code }.to_json,
        code: 200,
        msg: "OK"
      )
    end

    def respond_with_webauthn_polling_failure
      require "json"
      @data["#{@host}/api/v1/webauthn_verification/odow34b93t6aPCdY/status.json"] = Gem::HTTPResponseFactory.create(
        body: {
          status: "expired",
          message: "The token in the link you used has either expired or been used already.",
        }.to_json,
        code: 200,
        msg: "OK"
      )
    end

    def respond_with_require_otp
      response_fail = "You have enabled multifactor authentication"

      @data["#{host}/api/v1/api_key"] = proc do
        @call_count ||= 0
        if (@call_count += 1).odd?
          Gem::HTTPResponseFactory.create(body: response_fail, code: 401, msg: "Unauthorized")
        else
          Gem::HTTPResponseFactory.create(body: @api_key, code: 200, msg: "OK")
        end
      end
    end

    def respond_with_forbidden_api_key_response
      @data["#{host}/api/v1/api_key"] = Gem::HTTPResponseFactory.create(body: "Access Denied.", code: 403, msg: "Forbidden")
    end

    def respond_with_unauthorized_api_key_response
      response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."

      @data["#{host}/api/v1/api_key"] = Gem::HTTPResponseFactory.create(body: response, code: 401, msg: "Unauthorized")
    end
  end
end
