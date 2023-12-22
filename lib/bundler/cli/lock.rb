# frozen_string_literal: true

module Bundler
  class CLI::Lock
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      unless Bundler.default_gemfile
        Bundler.ui.error "Unable to find a Gemfile to lock"
        exit 1
      end

      print = options[:print]
      previous_ui_level = Bundler.ui.level
      Bundler.ui.level = "silent" if print

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      update = options[:update]
      conservative = options[:conservative]
      bundler = options[:bundler]

      if update.is_a?(Array) # unlocking specific gems
        Bundler::CLI::Common.ensure_all_gems_in_lockfile!(update)
        update = { gems: update, conservative: conservative }
      elsif update && conservative
        update = { conservative: conservative }
      elsif update && bundler
        update = { bundler: bundler }
      end

      Bundler.settings.temporary(frozen: false) do
        definition = Bundler.definition(update)

        Bundler::CLI::Common.configure_gem_version_promoter(definition, options) if options[:update]

        options["remove-platform"].each do |platform|
          definition.remove_platform(platform)
        end

        options["add-platform"].each do |platform_string|
          platform = Gem::Platform.new(platform_string)
          if platform.to_s == "unknown"
            Bundler.ui.warn "The platform `#{platform_string}` is unknown to RubyGems " \
              "and adding it will likely lead to resolution errors"
          end
          definition.add_platform(platform)
        end

        if definition.platforms.empty?
          raise InvalidOption, "Removing all platforms from the bundle is not allowed"
        end

        definition.resolve_remotely! unless options[:local]

        if print
          puts definition.to_lock
        else
          file = options[:lockfile]
          file = file ? File.expand_path(file) : Bundler.default_lockfile
          puts "Writing lockfile to #{file}"
          definition.lock(file)
        end
      end

      Bundler.ui.level = previous_ui_level
    end
  end
end
