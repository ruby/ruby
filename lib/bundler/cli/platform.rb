# frozen_string_literal: true

module Bundler
  class CLI::Platform
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      ruby_version = if Bundler.locked_gems
        Bundler.locked_gems.ruby_version&.gsub(/p\d+\Z/, "")
      else
        Bundler.definition.ruby_version&.single_version_string
      end

      output = []

      if options[:ruby]
        if ruby_version
          output << ruby_version
        else
          output << "No ruby version specified"
        end
      else
        platforms = Bundler.definition.platforms.map {|p| "* #{p}" }

        output << platform_info
        output << "Your app has gems that work on these platforms:\n#{platforms.join("\n")}"

        if ruby_version
          output << "Your Gemfile specifies a Ruby version requirement:\n* #{ruby_version}"

          begin
            Bundler.definition.validate_runtime!
            output << "Your current platform satisfies the Ruby version requirement."
          rescue RubyVersionMismatch => e
            output << e.message
          end
        else
          output << "Your Gemfile does not specify a Ruby version requirement."
        end
      end

      Bundler.ui.info output.join("\n\n")
    end

    private

    # `force_ruby_platform` decides which variant of a gem resolves, so a run
    # with it set can behave nothing like the local platform this command
    # reports. Say so, and say where it came from, since it is as likely to be
    # inherited from a config file as typed on the command line.
    def platform_info
      info = "Your platform is: #{Gem::Platform.local}"
      return info if Bundler.local_platform == Gem::Platform.local

      info + "\nHowever, your effective platform is: #{Bundler.local_platform} " \
        "(because force_ruby_platform is #{force_ruby_platform_origin})"
    end

    # Reuses Bundler's own accounting of where a setting came from, so the
    # explanation stays right for the environment, a local config, or a global
    # one, rather than assuming the environment variable.
    def force_ruby_platform_origin
      Bundler.settings.pretty_values_for(:force_ruby_platform).first.sub(/\ASet /, "set ")
    end
  end
end
