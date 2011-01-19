######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/remote_fetcher'

module Gem::GemcutterUtilities

  def sign_in
    return if Gem.configuration.rubygems_api_key

    say "Enter your RubyGems.org credentials."
    say "Don't have an account yet? Create one at http://rubygems.org/sign_up"

    email    =              ask "   Email: "
    password = ask_for_password "Password: "
    say "\n"

    response = rubygems_api_request :get, "api/v1/api_key" do |request|
      request.basic_auth email, password
    end

    with_response response do |resp|
      say "Signed in."
      Gem.configuration.rubygems_api_key = resp.body
    end
  end

  def rubygems_api_request(method, path, host = Gem.host, &block)
    require 'net/http'
    host = ENV['RUBYGEMS_HOST'] if ENV['RUBYGEMS_HOST']
    uri = URI.parse "#{host}/#{path}"

    request_method = Net::HTTP.const_get method.to_s.capitalize

    Gem::RemoteFetcher.fetcher.request(uri, request_method, &block)
  end

  def with_response(resp)
    case resp
    when Net::HTTPSuccess then
      if block_given? then
        yield resp
      else
        say resp.body
      end
    else
      say resp.body
      terminate_interaction 1
    end
  end

end
