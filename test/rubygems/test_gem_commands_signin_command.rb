# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/signin_command'
require 'rubygems/installer'

class TestGemCommandsSigninCommand < Gem::TestCase

  def setup
    super

    Gem.configuration.rubygems_api_key = nil
    Gem.configuration.api_keys.clear

    @cmd = Gem::Commands::SigninCommand.new
  end

  def teardown
    credentials_path = Gem.configuration.credentials_path
    File.delete(credentials_path)  if File.exist?(credentials_path)
    super
  end

  def test_execute_when_not_already_signed_in
    sign_in_ui = util_capture() { @cmd.execute }
    assert_match %r{Signed in.}, sign_in_ui.output
  end

  def test_execute_when_already_signed_in_with_same_host
    host            = 'http://some-gemcutter-compatible-host.org'
    sign_in_ui      = util_capture(nil, host) { @cmd.execute }
    old_credentials = YAML.load_file Gem.configuration.credentials_path

    sign_in_ui      = util_capture(nil, host) { @cmd.execute }
    new_credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal old_credentials[host], new_credentials[host]
  end

  def test_execute_when_already_signed_in_with_different_host
    api_key     = 'a5fdbb6ba150cbb83aad2bb2fede64cf04045xxxx'
    sign_in_ui  = util_capture(nil, nil, api_key) { @cmd.execute }
    host        = 'http://some-gemcutter-compatible-host.org'
    sign_in_ui  = util_capture(nil, host, api_key) { @cmd.execute }
    credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal credentials[:rubygems_api_key], api_key

    assert_equal credentials[host], nil
  end

  def test_execute_with_host_supplied
    host = 'http://some-gemcutter-compatible-host.org'

    sign_in_ui = util_capture(nil, host) { @cmd.execute }
    assert_match %r{Enter your #{host} credentials.}, sign_in_ui.output
    assert_match %r{Signed in.}, sign_in_ui.output

    api_key     = 'a5fdbb6ba150cbb83aad2bb2fede64cf040453903'
    credentials = YAML.load_file Gem.configuration.credentials_path
    assert_equal api_key, credentials[host]
  end

  def test_execute_with_valid_creds_set_for_default_host
    util_capture {@cmd.execute}

    api_key     = 'a5fdbb6ba150cbb83aad2bb2fede64cf040453903'
    credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal api_key, credentials[:rubygems_api_key]
  end

  # Utility method to capture IO/UI within the block passed

  def util_capture ui_stub = nil, host = nil, api_key = nil
    api_key ||= 'a5fdbb6ba150cbb83aad2bb2fede64cf040453903'
    response  = [api_key, 200, 'OK']
    email     = 'you@example.com'
    password  = 'secret'
    fetcher   = Gem::FakeFetcher.new

    # Set the expected response for the Web-API supplied
    ENV['RUBYGEMS_HOST']       = host || Gem::DEFAULT_HOST
    data_key                   = "#{ENV['RUBYGEMS_HOST']}/api/v1/api_key"
    fetcher.data[data_key]     = response
    Gem::RemoteFetcher.fetcher = fetcher

    sign_in_ui                 = ui_stub || Gem::MockGemUi.new("#{email}\n#{password}\n")

    use_ui sign_in_ui do
      yield
    end

    sign_in_ui
  end
end
