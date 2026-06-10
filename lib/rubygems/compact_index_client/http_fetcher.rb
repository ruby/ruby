# frozen_string_literal: true

require_relative "../remote_fetcher"

class Gem::CompactIndexClient
  # Fetches compact index files relative to +base_uri+ using
  # Gem::RemoteFetcher's connection infrastructure (proxy, TLS,
  # connection pooling). Implements the fetcher interface expected by
  # Gem::CompactIndexClient: #call(path, headers) returning a
  # Gem::Net::HTTP response.
  class HTTPFetcher
    REDIRECT_LIMIT = 10
    private_constant :REDIRECT_LIMIT

    def initialize(base_uri, remote_fetcher = Gem::RemoteFetcher.fetcher)
      base_uri = base_uri.to_s
      base_uri += "/" unless base_uri.end_with?("/")
      @base_uri = Gem::URI(base_uri)
      @remote_fetcher = remote_fetcher
    end

    def call(path, headers = {})
      fetch(@base_uri + path, headers, REDIRECT_LIMIT)
    end

    private

    def fetch(uri, headers, redirects_remaining)
      response = @remote_fetcher.request(uri, Gem::Net::HTTP::Get) do |req|
        headers.each {|name, value| req[name] = value }
      end

      case response
      when Gem::Net::HTTPSuccess, Gem::Net::HTTPNotModified
        response
      when Gem::Net::HTTPMovedPermanently, Gem::Net::HTTPFound, Gem::Net::HTTPSeeOther,
           Gem::Net::HTTPTemporaryRedirect
        raise Gem::RemoteFetcher::FetchError.new("too many redirects", uri) if redirects_remaining.zero?

        location = response["Location"]
        raise Gem::RemoteFetcher::FetchError.new("redirecting but no redirect location was given", uri) unless location

        fetch(uri + location, headers, redirects_remaining - 1)
      else
        raise Gem::RemoteFetcher::FetchError.new("bad response #{response.message} #{response.code}", uri)
      end
    end
  end
end
