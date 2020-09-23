# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/push_command'

class TestGemCommandsPushCommand < Gem::TestCase
  def setup
    super

    credential_setup

    ENV["RUBYGEMS_HOST"] = nil
    Gem.host = Gem::DEFAULT_HOST
    Gem.configuration.disable_default_gem_server = false

    @gems_dir  = File.join @tempdir, 'gems'
    @cache_dir = File.join @gemhome, "cache"

    FileUtils.mkdir @gems_dir

    Gem.configuration.rubygems_api_key =
      "ed244fbf2b1a52e012da8616c512fa47f9aa5250"

    @spec, @path = util_gem "freewill", "1.0.0"
    @host = 'https://rubygems.example'
    @api_key = Gem.configuration.rubygems_api_key

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    @cmd = Gem::Commands::PushCommand.new

    singleton_gem_class.class_eval do
      alias_method :orig_latest_rubygems_version, :latest_rubygems_version

      def latest_rubygems_version
        Gem.rubygems_version
      end
    end
  end

  def teardown
    credential_teardown

    super

    singleton_gem_class.class_eval do
      remove_method :latest_rubygems_version
      alias_method :latest_rubygems_version, :orig_latest_rubygems_version
    end
  end

  def send_battery
    use_ui @ui do
      @cmd.instance_variable_set :@host, @host
      @cmd.send_gem(@path)
    end

    assert_match %r{Pushing gem to #{@host}...}, @ui.output

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal File.size(@path), @fetcher.last_request["Content-Length"].to_i
    assert_equal "application/octet-stream", @fetcher.last_request["Content-Type"]
    assert_equal @api_key, @fetcher.last_request["Authorization"]

    assert_match @response, @ui.output
  end

  def test_execute
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = [@response, 200, 'OK']

    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_host
    host = 'https://other.example'

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{host}/api/v1/gems"] = [@response, 200, 'OK']
    @fetcher.data["#{Gem.host}/api/v1/gems"] =
      ['fail', 500, 'Internal Server Error']

    @cmd.options[:host] = host
    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_allowed_push_host
    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = "https://privategemserver.example"
    end

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@spec.metadata['allowed_push_host']}/api/v1/gems"] = [@response, 200, 'OK']
    @fetcher.data["#{Gem.host}/api/v1/gems"] =
      ['fail', 500, 'Internal Server Error']

    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_sending_when_default_host_disabled
    Gem.configuration.disable_default_gem_server = true
    response = "You must specify a gem server"

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @ui.error
  end

  def test_sending_when_default_host_disabled_with_override
    ENV["RUBYGEMS_HOST"] = @host
    Gem.configuration.disable_default_gem_server = true
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']

    send_battery
  end

  def test_sending_gem_to_metadata_host
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['default_gem_server'] = @host
    end

    @api_key = "EYKEY"

    keys = {
      :rubygems_api_key => 'KEY',
      @host => @api_key
    }

    FileUtils.mkdir_p File.dirname Gem.configuration.credentials_path
    File.open Gem.configuration.credentials_path, 'w' do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']

    send_battery
  end

  def test_sending_gem
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']

    send_battery
  end

  def test_sending_gem_to_allowed_push_host
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = @host
    end

    @api_key = "PRIVKEY"

    keys = {
      :rubygems_api_key => 'KEY',
      @host => @api_key
    }

    FileUtils.mkdir_p File.dirname Gem.configuration.credentials_path
    File.open Gem.configuration.credentials_path, 'w' do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']
    send_battery
  end

  def test_sending_gem_with_env_var_api_key
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = @host
    end

    @api_key = "PRIVKEY"
    ENV["GEM_HOST_API_KEY"] = "PRIVKEY"

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']
    send_battery
  end

  def test_sending_gem_to_allowed_push_host_with_basic_credentials
    @sanitized_host = "http://privategemserver.example"
    @host           = "http://user:password@privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = @sanitized_host
    end

    @api_key = "DOESNTMATTER"

    keys = {
      :rubygems_api_key => @api_key,
    }

    FileUtils.mkdir_p File.dirname Gem.configuration.credentials_path
    File.open Gem.configuration.credentials_path, 'w' do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, 'OK']
    send_battery
  end

  def test_sending_gem_to_disallowed_default_host
    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = "https://privategemserver.example"
    end

    response = %(ERROR:  "#{@host}" is not allowed by the gemspec, which only allows "https://privategemserver.example")

    assert_raises Gem::MockGemUi::TermError do
      send_battery
    end

    assert_match response, @ui.error
  end

  def test_sending_gem_to_disallowed_push_host
    @host = "https://anotherprivategemserver.example"
    push_host = "https://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata['allowed_push_host'] = push_host
    end

    @api_key = "PRIVKEY"

    keys = {
      :rubygems_api_key => 'KEY',
      @host => @api_key
    }

    FileUtils.mkdir_p File.dirname Gem.configuration.credentials_path
    File.open Gem.configuration.credentials_path, 'w' do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    response = "ERROR:  \"#{@host}\" is not allowed by the gemspec, which only allows \"#{push_host}\""

    assert_raises Gem::MockGemUi::TermError do
      send_battery
    end

    assert_match response, @ui.error
  end

  def test_sending_gem_defaulting_to_allowed_push_host
    host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata.delete('default_gem_server')
      spec.metadata['allowed_push_host'] = host
    end

    api_key = "PRIVKEY"

    keys = {
      host => api_key
    }

    FileUtils.mkdir_p File.dirname Gem.configuration.credentials_path
    File.open Gem.configuration.credentials_path, 'w' do |f|
      f.write keys.to_yaml
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{host}/api/v1/gems"] = [@response, 200, 'OK']

    # do not set @host
    use_ui(@ui) { @cmd.send_gem(@path) }

    assert_match %r{Pushing gem to #{host}...}, @ui.output

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal File.size(@path), @fetcher.last_request["Content-Length"].to_i
    assert_equal "application/octet-stream", @fetcher.last_request["Content-Type"]
    assert_equal api_key, @fetcher.last_request["Authorization"]

    assert_match @response, @ui.output
  end

  def test_raises_error_with_no_arguments
    def @cmd.sign_in(*); end
    assert_raises Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_sending_gem_denied
    response = "You don't have permission to push to this gem"
    @fetcher.data["#{@host}/api/v1/gems"] = [response, 403, 'Forbidden']
    @cmd.instance_variable_set :@host, @host

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @ui.output
  end

  def test_sending_gem_key
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = [@response, 200, "OK"]
    File.open Gem.configuration.credentials_path, 'a' do |f|
      f.write ':other: 701229f217cdf23b1344c7b4b54ca97'
    end
    Gem.configuration.load_api_keys

    @cmd.handle_options %w[-k other]
    @cmd.instance_variable_set :@host, @host
    @cmd.send_gem(@path)

    assert_equal Gem.configuration.api_keys[:other],
                 @fetcher.last_request["Authorization"]
  end

  def test_otp_verified_success
    response_fail = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    response_success = 'Successfully registered gem: freewill (1.0.0)'

    @fetcher.data["#{Gem.host}/api/v1/gems"] = [
      [response_fail, 401, 'Unauthorized'],
      [response_success, 200, 'OK']
    ]

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.send_gem(@path)
    end

    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_match response_success, @otp_ui.output
    assert_equal '111111', @fetcher.last_request['OTP']
  end

  def test_otp_verified_failure
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    @fetcher.data["#{Gem.host}/api/v1/gems"] = [response, 401, 'Unauthorized']

    @otp_ui = Gem::MockGemUi.new "111111\n"
    assert_raises Gem::MockGemUi::TermError do
      use_ui @otp_ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @otp_ui.output
    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_equal '111111', @fetcher.last_request['OTP']
  end

  private

  def singleton_gem_class
    class << Gem; self; end
  end
end
