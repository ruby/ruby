# frozen_string_literal: true
require 'rubygems/remote_fetcher'
require 'rubygems/text'

##
# Utility methods for using the RubyGems API.

module Gem::GemcutterUtilities

  include Gem::Text

  # TODO: move to Gem::Command
  OptionParser.accept Symbol do |value|
    value.to_sym
  end

  attr_writer :host

  ##
  # Add the --key option

  def add_key_option
    add_option('-k', '--key KEYNAME', Symbol,
               'Use the given API key',
               'from ~/.gem/credentials') do |value,options|
      options[:key] = value
    end
  end

  ##
  # Add the --otp option

  def add_otp_option
    add_option('--otp CODE',
               'Digit code for multifactor authentication') do |value, options|
      options[:otp] = value
    end
  end

  ##
  # The API key from the command options or from the user's configuration.

  def api_key
    if options[:key]
      verify_api_key options[:key]
    elsif Gem.configuration.api_keys.key?(host)
      Gem.configuration.api_keys[host]
    else
      Gem.configuration.rubygems_api_key
    end
  end

  ##
  # The host to connect to either from the RUBYGEMS_HOST environment variable
  # or from the user's configuration

  def host
    configured_host = Gem.host unless
      Gem.configuration.disable_default_gem_server

    @host ||=
      begin
        env_rubygems_host = ENV['RUBYGEMS_HOST']
        env_rubygems_host = nil if
          env_rubygems_host and env_rubygems_host.empty?

        env_rubygems_host|| configured_host
      end
  end

  ##
  # Creates an RubyGems API to +host+ and +path+ with the given HTTP +method+.
  #
  # If +allowed_push_host+ metadata is present, then it will only allow that host.

  def rubygems_api_request(method, path, host = nil, allowed_push_host = nil, &block)
    require 'net/http'

    self.host = host if host
    unless self.host
      alert_error "You must specify a gem server"
      terminate_interaction 1 # TODO: question this
    end

    if allowed_push_host
      allowed_host_uri = URI.parse(allowed_push_host)
      host_uri         = URI.parse(self.host)

      unless (host_uri.scheme == allowed_host_uri.scheme) && (host_uri.host == allowed_host_uri.host)
        alert_error "#{self.host.inspect} is not allowed by the gemspec, which only allows #{allowed_push_host.inspect}"
        terminate_interaction 1
      end
    end

    uri = URI.parse "#{self.host}/#{path}"

    request_method = Net::HTTP.const_get method.to_s.capitalize

    Gem::RemoteFetcher.fetcher.request(uri, request_method, &block)
  end

  ##
  # Signs in with the RubyGems API at +sign_in_host+ and sets the rubygems API
  # key.

  def sign_in(sign_in_host = nil)
    sign_in_host ||= self.host
    return if api_key

    pretty_host = if Gem::DEFAULT_HOST == sign_in_host
                    'RubyGems.org'
                  else
                    sign_in_host
                  end

    say "Enter your #{pretty_host} credentials."
    say "Don't have an account yet? " +
        "Create one at #{sign_in_host}/sign_up"

    email    =              ask "   Email: "
    password = ask_for_password "Password: "
    say "\n"

    response = rubygems_api_request(:get, "api/v1/api_key",
                                    sign_in_host) do |request|
      request.basic_auth email, password
    end

    if need_otp? response
      response = rubygems_api_request(:get, "api/v1/api_key", sign_in_host) do |request|
        request.basic_auth email, password
        request.add_field "OTP", options[:otp]
      end
    end

    with_response response do |resp|
      say "Signed in."
      set_api_key host, resp.body
    end
  end

  ##
  # Retrieves the pre-configured API key +key+ or terminates interaction with
  # an error.

  def verify_api_key(key)
    if Gem.configuration.api_keys.key? key
      Gem.configuration.api_keys[key]
    else
      alert_error "No such API key. Please add it to your configuration (done automatically on initial `gem push`)."
      terminate_interaction 1 # TODO: question this
    end
  end

  ##
  # If +response+ is an HTTP Success (2XX) response, yields the response if a
  # block was given or shows the response body to the user.
  #
  # If the response was not successful, shows an error to the user including
  # the +error_prefix+ and the response body.

  def with_response(response, error_prefix = nil)
    case response
    when Net::HTTPSuccess then
      if block_given?
        yield response
      else
        say clean_text(response.body)
      end
    else
      message = response.body
      message = "#{error_prefix}: #{message}" if error_prefix

      say clean_text(message)
      terminate_interaction 1 # TODO: question this
    end
  end

  ##
  # Returns true when the user has enabled multifactor authentication from
  # +response+ text.

  def need_otp?(response)
    return unless response.kind_of?(Net::HTTPUnauthorized) &&
        response.body.start_with?('You have enabled multifactor authentication')
    return true if options[:otp]

    say 'You have enabled multi-factor authentication. Please enter OTP code.'
    options[:otp] = ask 'Code: '
    true
  end

  def set_api_key(host, key)
    if host == Gem::DEFAULT_HOST
      Gem.configuration.rubygems_api_key = key
    else
      Gem.configuration.set_api_key host, key
    end
  end

end
