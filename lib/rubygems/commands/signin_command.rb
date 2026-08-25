# frozen_string_literal: true

require_relative "../command"
require_relative "../gemcutter_utilities"

class Gem::Commands::SigninCommand < Gem::Command
  include Gem::GemcutterUtilities

  def initialize
    super "signin", "Sign in to any gemcutter-compatible host. "\
          "It defaults to https://rubygems.org"

    add_option("--host HOST", "Push to another gemcutter-compatible host") do |value, options|
      options[:host] = value
    end

    add_otp_option
  end

  def description # :nodoc:
    "The signin command executes host sign in for a push server (the default is"\
    " https://rubygems.org). The host can be provided with the host flag or can"\
    " be inferred from the provided gem. Host resolution matches the resolution"\
    " strategy for the push command. If the :credential_store: gemrc option (or"\
    " RUBYGEMS_CREDENTIAL_STORE environment variable) is set, the resulting API key is"\
    " stored in the credential store it selects instead of ~/.gem/credentials."
  end

  def usage # :nodoc:
    program_name
  end

  def execute
    sign_in options[:host]
  end
end
