# frozen_string_literal: true

module Bundler
  class CLI::Doctor::SSL
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      return unless openssl_installed?

      output_ssl_environment
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

  end
end
