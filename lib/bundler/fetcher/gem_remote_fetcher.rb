# frozen_string_literal: true

require "rubygems/remote_fetcher"

module Bundler
  class Fetcher
    class GemRemoteFetcher < Gem::RemoteFetcher
      def initialize(*)
        super

        @pool_size = Bundler.settings.installation_parallelization
        ssl_ca_cert = Bundler.settings[:ssl_ca_cert]
        @cert_files << ssl_ca_cert if ssl_ca_cert
      end

      def request(*args)
        super do |req|
          req.delete("User-Agent") if headers["User-Agent"]
          yield req if block_given?
        end
      end
    end
  end
end
