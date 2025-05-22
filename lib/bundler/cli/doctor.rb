# frozen_string_literal: true

module Bundler
  class CLI::Doctor < Thor
    default_command(:diagnose)

    desc "diagnose [OPTIONS]", "Checks the bundle for common problems"
    long_desc <<-D
      Doctor scans the OS dependencies of each of the gems requested in the Gemfile. If
      missing dependencies are detected, Bundler prints them and exits status 1.
      Otherwise, Bundler prints a success message and exits with a status of 0.
    D
    method_option "gemfile", type: :string, banner: "Use the specified gemfile instead of Gemfile"
    method_option "quiet", type: :boolean, banner: "Only output warnings and errors."
    method_option "ssl", type: :boolean, default: false, banner: "Diagnose SSL problems."
    def diagnose
      require_relative "doctor/diagnose"
      Diagnose.new(options).run
    end

    desc "ssl [OPTIONS]", "Diagnose SSL problems"
    long_desc <<-D
      Diagnose SSL problems, especially related to certificates or TLS version while connecting to https://rubygems.org.
    D
    method_option "host", type: :string, banner: "The host to diagnose."
    method_option "tls-version", type: :string, banner: "Specify the SSL/TLS version when running the diagnostic. Accepts either <1.1> or <1.2>"
    method_option "verify-mode", type: :string, banner: "Specify the mode used for certification verification. Accepts either <peer> or <none>"
    def ssl
      require_relative "doctor/ssl"
      SSL.new(options).run
    end
  end
end
