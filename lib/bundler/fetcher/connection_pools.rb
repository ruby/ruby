# frozen_string_literal: true

require "rubygems/request"
require "rubygems/remote_fetcher"

module Bundler
  class Fetcher
    # Hands out pools of configured Gem::Net::HTTP connections, compatible
    # with the checkout/checkin interface that Gem::Request expects.
    # Connection policy (proxy, SSL, timeouts) follows Bundler settings
    # first, falling back to RubyGems configuration.
    class ConnectionPools
      # A fixed-size pool of connections to a single host, sharing the
      # interface of Gem::Request::HTTPPool.
      class Pool
        attr_reader :cert_files, :proxy_uri

        def initialize(connections, uri, proxy_uri, size)
          @connections = connections
          @uri = uri
          @proxy_uri = proxy_uri
          @cert_files = connections.cert_files
          @queue = Thread::SizedQueue.new(size)
          size.times { @queue.push(nil) }
        end

        def checkout
          @queue.pop || @connections.build_connection(@uri, @proxy_uri)
        end

        def checkin(connection)
          @queue.push(connection)
        end
      end

      attr_reader :override_headers, :cert_files

      def initialize(size:, timeout:)
        @size = size
        @timeout = timeout
        @override_headers = {}
        @cert_files = Gem::Request.get_cert_files
        @pools = {}
        @pool_mutex = Thread::Mutex.new
      end

      # Performs a GET request through Gem::Request, which handles resetting
      # and retrying stale connections, and returns the raw response.
      def request(uri, headers = nil)
        Gem::Request.new(uri, Gem::Net::HTTP::Get, nil, pool_for(uri)).fetch do |request|
          @override_headers.each {|key, value| request[key] = value }
          headers&.each {|key, value| request[key] = value }
        end
      end

      def pool_for(uri)
        key = [uri.scheme, uri.hostname, uri.port]
        @pool_mutex.synchronize do
          @pools[key] ||= Pool.new(self, uri, proxy_for(uri), @size)
        end
      end

      # The proxy that will be used for +uri+, or nil. RubyGems configuration
      # takes precedence over the environment, like Gem::RemoteFetcher.
      # Unlike Gem::Request, an https URI falls back to `http_proxy` when no
      # https-specific proxy is set, which is what the previous
      # net-http-persistent based transport did.
      def proxy_for(uri)
        proxy = if config_proxy = Gem.configuration[:http_proxy]
          Gem::Request.proxy_uri(config_proxy)
        else
          env_proxy_for(uri)
        end
        return unless proxy
        return unless Gem::URI::Generic.use_proxy?(uri.hostname, nil, uri.port, no_proxy_env)
        proxy
      end

      def build_connection(uri, proxy_uri) # :nodoc:
        args = [uri.hostname, uri.port]
        args += if proxy_uri
          [proxy_uri.hostname, proxy_uri.port,
           Gem::UriFormatter.new(proxy_uri.user).unescape,
           Gem::UriFormatter.new(proxy_uri.password).unescape]
        else
          [nil, nil]
        end

        connection = Gem::Request::ConnectionPools.client.new(*args)
        configure_ssl(connection) if uri.scheme == "https"
        connection.open_timeout = @timeout
        connection.read_timeout = @timeout
        connection.start
        connection
      end

      private

      def env_proxy_for(uri)
        proxy = Gem::Request.get_proxy_from_env(uri.scheme)
        proxy = Gem::Request.get_proxy_from_env("http") if proxy == :no_proxy && uri.scheme == "https"
        proxy == :no_proxy ? nil : proxy
      end

      def no_proxy_env
        ENV["no_proxy"] || ENV["NO_PROXY"] || ""
      end

      def configure_ssl(connection)
        connection.use_ssl = true
        connection.verify_mode = Bundler.settings[:ssl_verify_mode] || OpenSSL::SSL::VERIFY_PEER
        connection.cert_store = bundler_cert_store

        ssl_client_cert = Bundler.settings[:ssl_client_cert] ||
                          (Gem.configuration.ssl_client_cert if
                            Gem.configuration.respond_to?(:ssl_client_cert))
        return unless ssl_client_cert

        pem = File.read(ssl_client_cert)
        connection.cert = OpenSSL::X509::Certificate.new(pem)
        connection.key  = OpenSSL::PKey.read(pem)
      end

      def bundler_cert_store
        store = OpenSSL::X509::Store.new
        ssl_ca_cert = Bundler.settings[:ssl_ca_cert] ||
                      (Gem.configuration.ssl_ca_cert if
                        Gem.configuration.respond_to?(:ssl_ca_cert))
        if ssl_ca_cert
          if File.directory? ssl_ca_cert
            store.add_path ssl_ca_cert
          else
            store.add_file ssl_ca_cert
          end
        else
          store.set_default_paths
          cert_files.each {|c| store.add_file c }
        end
        store
      end
    end
  end
end
