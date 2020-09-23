# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/owner_command'

class TestGemCommandsOwnerCommand < Gem::TestCase

  def setup
    super

    credential_setup

    ENV["RUBYGEMS_HOST"] = nil
    @stub_ui = Gem::MockGemUi.new
    @stub_fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @stub_fetcher
    Gem.configuration = nil
    Gem.configuration.rubygems_api_key = "ed244fbf2b1a52e012da8616c512fa47f9aa5250"

    @cmd = Gem::Commands::OwnerCommand.new
  end

  def teardown
    credential_teardown

    super
  end

  def test_show_owners
    response = <<EOF
---
- email: user1@example.com
  id: 1
  handle: user1
- email: user2@example.com
- id: 3
  handle: user3
- id: 4
EOF

    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners.yaml"] = [response, 200, 'OK']

    use_ui @stub_ui do
      @cmd.show_owners("freewill")
    end

    assert_equal Net::HTTP::Get, @stub_fetcher.last_request.class
    assert_equal Gem.configuration.rubygems_api_key, @stub_fetcher.last_request["Authorization"]

    assert_match %r{Owners for gem: freewill}, @stub_ui.output
    assert_match %r{- user1@example.com}, @stub_ui.output
    assert_match %r{- user2@example.com}, @stub_ui.output
    assert_match %r{- user3}, @stub_ui.output
    assert_match %r{- 4}, @stub_ui.output
  end

  def test_show_owners_dont_load_objects
    skip "testing a psych-only API" unless defined?(::Psych::DisallowedClass)

    response = <<EOF
---
- email: !ruby/object:Object {}
  id: 1
  handle: user1
- email: user2@example.com
- id: 3
  handle: user3
- id: 4
EOF

    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners.yaml"] = [response, 200, 'OK']

    assert_raises Psych::DisallowedClass do
      use_ui @ui do
        @cmd.show_owners("freewill")
      end
    end
  end

  def test_show_owners_setting_up_host_through_env_var
    response = "- email: user1@example.com\n"
    host = "http://rubygems.example"
    ENV["RUBYGEMS_HOST"] = host

    @stub_fetcher.data["#{host}/api/v1/gems/freewill/owners.yaml"] = [response, 200, 'OK']

    use_ui @stub_ui do
      @cmd.show_owners("freewill")
    end

    assert_match %r{Owners for gem: freewill}, @stub_ui.output
    assert_match %r{- user1@example.com}, @stub_ui.output
  end

  def test_show_owners_setting_up_host
    response = "- email: user1@example.com\n"
    host = "http://rubygems.example"
    @cmd.host = host

    @stub_fetcher.data["#{host}/api/v1/gems/freewill/owners.yaml"] = [response, 200, 'OK']

    use_ui @stub_ui do
      @cmd.show_owners("freewill")
    end

    assert_match %r{Owners for gem: freewill}, @stub_ui.output
    assert_match %r{- user1@example.com}, @stub_ui.output
  end

  def test_show_owners_denied
    response = "You don't have permission to push to this gem"
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners.yaml"] = [response, 403, 'Forbidden']

    assert_raises Gem::MockGemUi::TermError do
      use_ui @stub_ui do
        @cmd.show_owners("freewill")
      end
    end

    assert_match response, @stub_ui.output
  end

  def test_show_owners_key
    response = "- email: user1@example.com\n"
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners.yaml"] = [response, 200, 'OK']
    File.open Gem.configuration.credentials_path, 'a' do |f|
      f.write ':other: 701229f217cdf23b1344c7b4b54ca97'
    end
    Gem.configuration.load_api_keys

    @cmd.handle_options %w[-k other]
    @cmd.show_owners('freewill')

    assert_equal '701229f217cdf23b1344c7b4b54ca97', @stub_fetcher.last_request['Authorization']
  end

  def test_add_owners
    response = "Owner added successfully."
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 200, 'OK']

    use_ui @stub_ui do
      @cmd.add_owners("freewill", ["user-new1@example.com"])
    end

    assert_equal Net::HTTP::Post, @stub_fetcher.last_request.class
    assert_equal Gem.configuration.rubygems_api_key, @stub_fetcher.last_request["Authorization"]
    assert_equal "email=user-new1%40example.com", @stub_fetcher.last_request.body

    assert_match response, @stub_ui.output
  end

  def test_add_owners_denied
    response = "You don't have permission to push to this gem"
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 403, 'Forbidden']

    use_ui @stub_ui do
      @cmd.add_owners("freewill", ["user-new1@example.com"])
    end

    assert_match response, @stub_ui.output
  end

  def test_add_owner_with_host_option_through_execute
    host = "http://rubygems.example"
    add_owner_response = "Owner added successfully."
    show_owners_response = "- email: user1@example.com\n"
    @stub_fetcher.data["#{host}/api/v1/gems/freewill/owners"] = [add_owner_response, 200, 'OK']
    @stub_fetcher.data["#{host}/api/v1/gems/freewill/owners.yaml"] = [show_owners_response, 200, 'OK']

    @cmd.handle_options %W[--host #{host} --add user-new1@example.com freewill]

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_match add_owner_response, @stub_ui.output
    assert_match %r{Owners for gem: freewill}, @stub_ui.output
    assert_match %r{- user1@example.com}, @stub_ui.output
  end

  def test_add_owners_key
    response = "Owner added successfully."
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 200, 'OK']
    File.open Gem.configuration.credentials_path, 'a' do |f|
      f.write ':other: 701229f217cdf23b1344c7b4b54ca97'
    end
    Gem.configuration.load_api_keys

    @cmd.handle_options %w[-k other]
    @cmd.add_owners('freewill', ['user-new1@example.com'])

    assert_equal '701229f217cdf23b1344c7b4b54ca97', @stub_fetcher.last_request['Authorization']
  end

  def test_remove_owners
    response = "Owner removed successfully."
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 200, 'OK']

    use_ui @stub_ui do
      @cmd.remove_owners("freewill", ["user-remove1@example.com"])
    end

    assert_equal Net::HTTP::Delete, @stub_fetcher.last_request.class
    assert_equal Gem.configuration.rubygems_api_key, @stub_fetcher.last_request["Authorization"]
    assert_equal "email=user-remove1%40example.com", @stub_fetcher.last_request.body

    assert_match response, @stub_ui.output
  end

  def test_remove_owners_denied
    response = "You don't have permission to push to this gem"
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 403, 'Forbidden']

    use_ui @stub_ui do
      @cmd.remove_owners("freewill", ["user-remove1@example.com"])
    end

    assert_match response, @stub_ui.output
  end

  def test_remove_owners_key
    response = "Owner removed successfully."
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 200, 'OK']
    File.open Gem.configuration.credentials_path, 'a' do |f|
      f.write ':other: 701229f217cdf23b1344c7b4b54ca97'
    end
    Gem.configuration.load_api_keys

    @cmd.handle_options %w[-k other]
    @cmd.remove_owners('freewill', ['user-remove1@example.com'])

    assert_equal '701229f217cdf23b1344c7b4b54ca97', @stub_fetcher.last_request['Authorization']
  end

  def test_remove_owners_missing
    response = 'Owner could not be found.'
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 404, 'Not Found']

    use_ui @stub_ui do
      @cmd.remove_owners("freewill", ["missing@example"])
    end

    assert_equal "Removing missing@example: #{response}\n", @stub_ui.output
  end

  def test_otp_verified_success
    response_fail = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    response_success = "Owner added successfully."

    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [
      [response_fail, 401, 'Unauthorized'],
      [response_success, 200, 'OK']
    ]

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.add_owners("freewill", ["user-new1@example.com"])
    end

    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_match response_success, @otp_ui.output
    assert_equal '111111', @stub_fetcher.last_request['OTP']
  end

  def test_otp_verified_failure
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    @stub_fetcher.data["#{Gem.host}/api/v1/gems/freewill/owners"] = [response, 401, 'Unauthorized']

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.add_owners("freewill", ["user-new1@example.com"])
    end

    assert_match response, @otp_ui.output
    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_equal '111111', @stub_fetcher.last_request['OTP']
  end

end
