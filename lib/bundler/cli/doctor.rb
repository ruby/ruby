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
    def diagnose
      require_relative "doctor/diagnose"
      Diagnose.new(options).run
    end
  end
end
