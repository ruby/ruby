# frozen_string_literal: true

require_relative "shared_helpers"

if Bundler::SharedHelpers.in_bundle?
  require_relative "../bundler"

  if STDOUT.tty? || ENV["BUNDLER_FORCE_TTY"]
    Bundler.ui = Bundler::UI::Shell.new
    begin
      Bundler.setup
    rescue Bundler::BundlerError => e
      Bundler.ui.warn "\e[31m#{e.message}\e[0m"
      Bundler.ui.warn e.backtrace.join("\n") if ENV["DEBUG"]
      if e.is_a?(Bundler::GemNotFound)
        Bundler.ui.warn "\e[33mRun `bundle install` to install missing gems.\e[0m"
      end
      exit e.status_code
    end
  else
    Bundler.setup
  end

  # Add bundler to the load path after disabling system gems
  bundler_lib = File.expand_path("../..", __FILE__)
  $LOAD_PATH.unshift(bundler_lib) unless $LOAD_PATH.include?(bundler_lib)

  Bundler.ui = nil
end
