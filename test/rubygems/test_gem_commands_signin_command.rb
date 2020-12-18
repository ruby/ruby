# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/signin_command'
require 'rubygems/installer'

class TestGemCommandsSigninCommand < Gem::TestCase
  def setup
    super

    credential_setup

    Gem.configuration.rubygems_api_key = nil
    Gem.configuration.api_keys.clear

    @cmd = Gem::Commands::SigninCommand.new
  end

  def teardown
    credential_teardown

    super
  end

  def test_execute_when_not_already_signed_in
    sign_in_ui = util_capture { @cmd.execute }
    assert_match %r{Signed in.}, sign_in_ui.output
  end

  def test_execute_when_already_signed_in_with_same_host
    host = 'http://some-gemcutter-compatible-host.org'

    util_capture(nil, host) { @cmd.execute }
    old_credentials = YAML.load_file Gem.configuration.credentials_path

    util_capture(nil, host) { @cmd.execute }
    new_credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal old_credentials[host], new_credentials[host]
  end

  def test_execute_when_already_signed_in_with_different_host
    api_key = 'a5fdbb6ba150cbb83aad2bb2fede64cf04045xxxx'

    util_capture(nil, nil, api_key) { @cmd.execute }
    host = 'http://some-gemcutter-compatible-host.org'

    util_capture(nil, host, api_key) { @cmd.execute }
    credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal credentials[:rubygems_api_key], api_key

    assert_nil credentials[host]
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
    util_capture { @cmd.execute }

    api_key     = 'a5fdbb6ba150cbb83aad2bb2fede64cf040453903'
    credentials = YAML.load_file Gem.configuration.credentials_path

    assert_equal api_key, credentials[:rubygems_api_key]
  end

  def test_excute_with_key_name_and_scope
    email     = 'you@example.com'
    password  = 'secret'
    api_key   = '1234'
    fetcher   = Gem::RemoteFetcher.fetcher

    key_name_ui = Gem::MockGemUi.new "#{email}\n#{password}\ntest-key\n\ny\n\n\n\n\n\n"
    util_capture(key_name_ui, nil, api_key, fetcher) { @cmd.execute }

    user = ENV["USER"] || ENV["USERNAME"]

    assert_match "API Key name [#{Socket.gethostname}-#{user}", key_name_ui.output
    assert_match "index_rubygems [y/N]", key_name_ui.output
    assert_match "push_rubygem [y/N]", key_name_ui.output
    assert_match "yank_rubygem [y/N]", key_name_ui.output
    assert_match "add_owner [y/N]", key_name_ui.output
    assert_match "remove_owner [y/N]", key_name_ui.output
    assert_match "access_webhooks [y/N]", key_name_ui.output
    assert_match "show_dashboard [y/N]", key_name_ui.output
    assert_equal "name=test-key&push_rubygem=true", fetcher.last_request.body

    credentials = YAML.load_file Gem.configuration.credentials_path
    assert_equal api_key, credentials[:rubygems_api_key]
  end

  # Utility method to capture IO/UI within the block passed

  def util_capture(ui_stub = nil, host = nil, api_key = nil, fetcher = Gem::FakeFetcher.new)
    api_key ||= 'a5fdbb6ba150cbb83aad2bb2fede64cf040453903'
    response  = [api_key, 200, 'OK']
    email     = 'you@example.com'
    password  = 'secret'

    # Set the expected response for the Web-API supplied
    ENV['RUBYGEMS_HOST']       = host || Gem::DEFAULT_HOST
    data_key                   = "#{ENV['RUBYGEMS_HOST']}/api/v1/api_key"
    fetcher.data[data_key]     = response
    Gem::RemoteFetcher.fetcher = fetcher

    sign_in_ui = ui_stub || Gem::MockGemUi.new("#{email}\n#{password}\n\n\n\n\n\n\n\n\n")

    use_ui sign_in_ui do
      yield
    end

    sign_in_ui
  end
end
