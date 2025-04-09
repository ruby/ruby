# frozen_string_literal: true

require "rubygems/remote_fetcher"
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
      rubygem_success = rubygem_connection_successful?

      return unless net_http_connection_successful?
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

    def rubygem_connection_successful?
      Gem::RemoteFetcher.fetcher.fetch_path(uri)
      Bundler.ui.info("RubyGems:      success")

      true
    rescue StandardError => error
      Bundler.ui.warn("RubyGems:      failed     (#{Explanation.explain_bundler_or_rubygems_error(error)})")

      false
    end

    def net_http_connection_successful?
      ::Gem::Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = true
        http.min_version = tls_version
        http.max_version = tls_version
        http.verify_mode = verify_mode
      end.start

      Bundler.ui.info("Ruby net/http: success")

      true
    rescue StandardError => error
      Bundler.ui.warn(<<~MSG)
        Ruby net/http: failed

        Unfortunately, this Ruby can't connect to #{host}.

        #{Explanation.explain_net_http_error(error, host, tls_version)}
      MSG

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

      def explain_net_http_error(error, host, tls_version)
        case error.message
        # Check for certificate errors
        when /certificate verify failed/
          <<~MSG
            #{show_ssl_certs}
            Your Ruby can't connect to #{host} because you are missing the certificate files OpenSSL needs to verify you are connecting to the genuine #{host} servers.
          MSG
        # Check for TLS version errors
        when /read server hello A/, /tlsv1 alert protocol version/
          if tls_version.to_s == "TLS1_3"
            "Your Ruby can't connect to #{host} because #{tls_version} isn't supported yet.\n"
          else
            <<~MSG
              Your Ruby can't connect to #{host} because your version of OpenSSL is too old.
              You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL.
            MSG
          end
        # OpenSSL doesn't support TLS version specified by argument
        when /unknown SSL method/
          "Your Ruby can't connect because #{tls_version} isn't supported by your version of OpenSSL."
        else
          <<~MSG
            Even worse, we're not sure why.

            Here's the full error information:
            #{error.class}: #{error.message}
              #{error.backtrace.join("\n  ")}

            You might have more luck using Mislav's SSL doctor.rb script. You can get it here:
            https://github.com/mislav/ssl-tools/blob/8b3dec4/doctor.rb

            Read more about the script and how to use it in this blog post:
            https://mislav.net/2013/07/ruby-openssl/
          MSG
        end
      end

      private

      def show_ssl_certs
        ssl_cert_file = ENV["SSL_CERT_FILE"] || OpenSSL::X509::DEFAULT_CERT_FILE
        ssl_cert_dir  = ENV["SSL_CERT_DIR"]  || OpenSSL::X509::DEFAULT_CERT_DIR

        <<~MSG
          Below affect only Ruby net/http connections:
          SSL_CERT_FILE: #{File.exist?(ssl_cert_file) ? "exists     #{ssl_cert_file}" : "is missing #{ssl_cert_file}"}
          SSL_CERT_DIR:  #{Dir.exist?(ssl_cert_dir)   ? "exists     #{ssl_cert_dir}"  : "is missing #{ssl_cert_dir}"}
        MSG
      end
    end
  end
end
