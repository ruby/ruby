# frozen_string_literal: true

require "rubygems/remote_fetcher"

module Bundler
  # Adds support for setting custom HTTP headers when fetching gems from the
  # server.
  #
  # TODO: Get rid of this when and if gemstash only supports RubyGems versions
  # that contain https://github.com/rubygems/rubygems/commit/3db265cc20b2f813.
  class GemRemoteFetcher < Gem::RemoteFetcher
    attr_accessor :headers

    # Extracted from RubyGems 2.4.
    def fetch_http(uri, last_modified = nil, head = false, depth = 0)
      fetch_type = head ? Net::HTTP::Head : Net::HTTP::Get
      # beginning of change
      response   = request uri, fetch_type, last_modified do |req|
        headers.each {|k, v| req.add_field(k, v) } if headers
      end
      # end of change

      case response
      when Net::HTTPOK, Net::HTTPNotModified then
        response.uri = uri if response.respond_to? :uri
        head ? response : response.body
      when Net::HTTPMovedPermanently, Net::HTTPFound, Net::HTTPSeeOther,
           Net::HTTPTemporaryRedirect then
        raise FetchError.new("too many redirects", uri) if depth > 10

        location = URI.parse response["Location"]

        if https?(uri) && !https?(location)
          raise FetchError.new("redirecting to non-https resource: #{location}", uri)
        end

        fetch_http(location, last_modified, head, depth + 1)
      else
        raise FetchError.new("bad response #{response.message} #{response.code}", uri)
      end
    end
  end
end
