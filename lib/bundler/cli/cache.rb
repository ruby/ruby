# frozen_string_literal: true

module Bundler
  class CLI::Cache
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      Bundler.definition.validate_runtime!
      Bundler.definition.resolve_with_cache!
      setup_cache_all
      Bundler.settings.set_command_option_if_given :cache_all_platforms, options["all-platforms"]
      Bundler.load.cache
      Bundler.settings.set_command_option_if_given :no_prune, options["no-prune"]
      Bundler.load.lock
    rescue GemNotFound => e
      Bundler.ui.error(e.message)
      Bundler.ui.warn "Run `bundle install` to install missing gems."
      exit 1
    end

  private

    def setup_cache_all
      Bundler.settings.set_command_option_if_given :cache_all, options[:all]

      if Bundler.definition.has_local_dependencies? && !Bundler.feature_flag.cache_all?
        Bundler.ui.warn "Your Gemfile contains path and git dependencies. If you want "    \
          "to package them as well, please pass the --all flag. This will be the default " \
          "on Bundler 3.0."
      end
    end
  end
end
