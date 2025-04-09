# frozen_string_literal: true

require "uri"

module Bundler
  class CLI::Doctor::SSL
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      return unless openssl_installed?

      output_ssl_environment
      bundler_success = bundler_connection_successful?
    end

    private

    def host
      @options[:host] || "rubygems.org"
    end

    def tls_version
      @options[:"tls-version"].then do |version|
        "TLS#{version.sub(".", "_")}".to_sym if version
      end
    end

    def verify_mode
      mode = @options[:"verify-mode"] || :peer

      @verify_mode ||= mode.then {|mod| OpenSSL::SSL.const_get("verify_#{mod}".upcase) }
    end

    def uri
      @uri ||= URI("https://#{host}")
    end

    def openssl_installed?
      require "openssl"

      true
    rescue LoadError
      Bundler.ui.warn(<<~MSG)
        Oh no! Your Ruby doesn't have OpenSSL, so it can't connect to #{host}.
        You'll need to recompile or reinstall Ruby with OpenSSL support and try again.
      MSG

      false
    end

    def output_ssl_environment
      Bundler.ui.info(<<~MESSAGE)
        Here's your OpenSSL environment:

        OpenSSL:       #{OpenSSL::VERSION}
        Compiled with: #{OpenSSL::OPENSSL_VERSION}
        Loaded with:   #{OpenSSL::OPENSSL_LIBRARY_VERSION}
      MESSAGE
    end

    def bundler_connection_successful?
      Bundler.ui.info("\nTrying connections to #{uri}:\n")

      bundler_uri = Gem::URI(uri.to_s)
      Bundler::Fetcher.new(
        Bundler::Source::Rubygems::Remote.new(bundler_uri)
      ).send(:connection).request(bundler_uri)

      Bundler.ui.info("Bundler:       success")

      true
    rescue StandardError => error
      Bundler.ui.warn("Bundler:       failed     (#{Explanation.explain_bundler_or_rubygems_error(error)})")

      false
    end

    module Explanation
      extend self

      def explain_bundler_or_rubygems_error(error)
        case error.message
        when /certificate verify failed/
          "certificate verification"
        when /read server hello A/
          "SSL/TLS protocol version mismatch"
        when /tlsv1 alert protocol version/
          "requested TLS version is too old"
        else
          error.message
        end
      end
    end
  end
end
