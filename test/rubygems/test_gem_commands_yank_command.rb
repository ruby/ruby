# frozen_string_literal: true

require_relative "helper"
require_relative "multifactor_auth_utilities"
require "rubygems/commands/yank_command"

class TestGemCommandsYankCommand < Gem::TestCase
  def setup
    super

    credential_setup

    @cmd = Gem::Commands::YankCommand.new
    @cmd.options[:host] = "http://example"

    @fetcher = Gem::MultifactorAuthFetcher.new(host: "http://example")
    Gem::RemoteFetcher.fetcher = @fetcher

    Gem.configuration.rubygems_api_key = "key"
    Gem.configuration.api_keys[:KEY] = "other"
  end

  def teardown
    credential_teardown

    super
  end

  def test_handle_options
    @cmd.handle_options %w[a --version 1.0 --platform x86-darwin -k KEY --host HOST]

    assert_equal %w[a],        @cmd.options[:args]
    assert_equal :KEY,         @cmd.options[:key]
    assert_equal "HOST",       @cmd.options[:host]
    assert_nil                 @cmd.options[:platform]
    assert_equal req("= 1.0"), @cmd.options[:version]
  end

  def test_handle_options_missing_argument
    %w[-v --version -p --platform].each do |option|
      assert_raise Gem::OptionParser::MissingArgument do
        @cmd.handle_options %W[a #{option}]
      end
    end
  end

  def test_execute
    yank_uri = "http://example/api/v1/gems/yank"
    @fetcher.data[yank_uri] = HTTPResponseFactory.create(body: "Successfully yanked", code: 200, msg: "OK")

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Yanking gem from http://example}, @ui.output
    assert_match %r{Successfully yanked}, @ui.output

    platform = Gem.platforms[1]
    body = @fetcher.last_request.body.split("&").sort
    assert_equal %W[gem_name=a platform=#{platform} version=1.0], body

    assert_equal "key", @fetcher.last_request["Authorization"]

    assert_equal [yank_uri], @fetcher.paths
  end

  def test_execute_with_otp_success
    response_fail = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    yank_uri = "http://example/api/v1/gems/yank"
    @fetcher.data[yank_uri] = [
      HTTPResponseFactory.create(body: response_fail, code: 401, msg: "Unauthorized"),
      HTTPResponseFactory.create(body: "Successfully yanked", code: 200, msg: "OK"),
    ]

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.execute
    end

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @otp_ui.output
    assert_match "Code: ", @otp_ui.output
    assert_match %r{Yanking gem from http://example}, @otp_ui.output
    assert_match %r{Successfully yanked}, @otp_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_execute_with_otp_failure
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    yank_uri = "http://example/api/v1/gems/yank"
    @fetcher.data[yank_uri] = HTTPResponseFactory.create(body: response, code: 401, msg: "Unauthorized")

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.execute
    end

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @otp_ui.output
    assert_match response, @otp_ui.output
    assert_match "Code: ", @otp_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_with_webauthn_enabled_success
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("http://example/api/v1/gems/yank", "Successfully yanked")
    @fetcher.respond_with_webauthn_url

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    TCPServer.stub(:new, server) do
      Gem::GemcutterUtilities::WebauthnListener.stub(:listener_thread, Thread.new { Thread.current[:otp] = "Uvh6T57tkWuUnWYo" }) do
        use_ui @ui do
          @cmd.execute
        end
      end
    end

    assert_match %r{Yanking gem from http://example}, @ui.output
    assert_match "You have enabled multi-factor authentication. Please visit #{@fetcher.webauthn_url_with_port(server.port)} " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
    assert_match "Successfully yanked", @ui.output
  end

  def test_with_webauthn_enabled_failure
    server = Gem::MockTCPServer.new
    error = Gem::WebauthnVerificationError.new("Something went wrong")

    @fetcher.respond_with_require_otp("http://example/api/v1/gems/yank", "Successfully yanked")
    @fetcher.respond_with_webauthn_url

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    error = assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        Gem::GemcutterUtilities::WebauthnListener.stub(:listener_thread, Thread.new { Thread.current[:error] = error }) do
          use_ui @ui do
            @cmd.execute
          end
        end
      end
    end
    assert_equal 1, error.exit_code

    assert_match @fetcher.last_request["Authorization"], Gem.configuration.rubygems_api_key
    assert_match %r{Yanking gem from http://example}, @ui.output
    assert_match "You have enabled multi-factor authentication. Please visit #{@fetcher.webauthn_url_with_port(server.port)} " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match "ERROR:  Security device verification failed: Something went wrong", @ui.error
    refute_match "You are verified with a security device. You may close the browser window.", @ui.output
    refute_match "Successfully yanked", @ui.output
  end

  def test_with_webauthn_enabled_success_with_polling
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("http://example/api/v1/gems/yank", "Successfully yanked")
    @fetcher.respond_with_webauthn_url
    @fetcher.respond_with_webauthn_polling("Uvh6T57tkWuUnWYo")

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    TCPServer.stub(:new, server) do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r{Yanking gem from http://example}, @ui.output
    assert_match "You have enabled multi-factor authentication. Please visit #{@fetcher.webauthn_url_with_port(server.port)} " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
    assert_match "Successfully yanked", @ui.output
  end

  def test_with_webauthn_enabled_failure_with_polling
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("http://example/api/v1/gems/yank", "Successfully yanked")
    @fetcher.respond_with_webauthn_url
    @fetcher.respond_with_webauthn_polling_failure

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")

    error = assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        use_ui @ui do
          @cmd.execute
        end
      end
    end
    assert_equal 1, error.exit_code

    assert_match @fetcher.last_request["Authorization"], Gem.configuration.rubygems_api_key
    assert_match %r{Yanking gem from http://example}, @ui.output
    assert_match "You have enabled multi-factor authentication. Please visit #{@fetcher.webauthn_url_with_port(server.port)} " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match "ERROR:  Security device verification failed: The token in the link you used has either expired " \
      "or been used already.", @ui.error
    refute_match "You are verified with a security device. You may close the browser window.", @ui.output
    refute_match "Successfully yanked", @ui.output
  end

  def test_execute_key
    yank_uri = "http://example/api/v1/gems/yank"
    @fetcher.data[yank_uri] = HTTPResponseFactory.create(body: "Successfully yanked", code: 200, msg: "OK")

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req("= 1.0")
    @cmd.options[:key]     = :KEY

    use_ui @ui do
      @cmd.execute
    end

    body = @fetcher.last_request.body.split("&").sort
    assert_equal %w[gem_name=a version=1.0], body
    assert_equal "other", @fetcher.last_request["Authorization"]
  end

  def test_execute_host
    host = "https://other.example"
    yank_uri = "#{host}/api/v1/gems/yank"
    @fetcher.data[yank_uri] = HTTPResponseFactory.create(body: "Successfully yanked", code: 200, msg: "OK")

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req("= 1.0")
    @cmd.options[:host]    = host

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Yanking gem from https://other.example}, @ui.output
    assert_match %r{Successfully yanked}, @ui.output

    body = @fetcher.last_request.body.split("&").sort
    assert_equal %w[gem_name=a version=1.0], body
    assert_equal "key", @fetcher.last_request["Authorization"]
    assert_equal [yank_uri], @fetcher.paths
  end

  def test_yank_gem_unathorized_api_key
    response_forbidden = "The API key doesn't have access"
    response_success   = "Successfully yanked"
    host               = "http://example"

    @fetcher.data["#{host}/api/v1/gems/yank"] = [
      HTTPResponseFactory.create(body: response_forbidden, code: 403, msg: "Forbidden"),
      HTTPResponseFactory.create(body: response_success, code: 200, msg: "OK"),
    ]

    @fetcher.data["#{host}/api/v1/api_key"] = HTTPResponseFactory.create(body: "", code: 200, msg: "OK")
    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req("= 1.0")
    @cmd.instance_variable_set :@host, host
    @cmd.instance_variable_set :@scope, :yank_rubygem

    @ui = Gem::MockGemUi.new "some@mail.com\npass\n"
    use_ui @ui do
      @cmd.execute
    end

    access_notice = "The existing key doesn't have access of yank_rubygem on http://example. Please sign in to update access."
    assert_match access_notice, @ui.output
    assert_match "Email:", @ui.output
    assert_match "Password:", @ui.output
    assert_match "Added yank_rubygem scope to the existing API key", @ui.output
    assert_match response_success, @ui.output
  end
end
