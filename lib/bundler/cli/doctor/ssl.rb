# frozen_string_literal: true

module Bundler
  class CLI::Doctor::SSL
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
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
  end
end
