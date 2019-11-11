# frozen_string_literal: true

module Bundler
  class CLI::Cache
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]
      Bundler.settings.set_command_option_if_given :path, options[:path]
      Bundler.settings.set_command_option_if_given :cache_path, options["cache-path"]

      setup_cache_all
      install

      # TODO: move cache contents here now that all bundles are locked
      custom_path = Bundler.settings[:path] if options[:path]

      Bundler.settings.temporary(:cache_all_platforms => options["all-platforms"]) do
        Bundler.load.cache(custom_path)
      end
    end

  private

    def install
      require_relative "install"
      options = self.options.dup
      options["local"] = false if Bundler.settings[:cache_all_platforms]
      Bundler::CLI::Install.new(options).run
    end

    def setup_cache_all
      all = options.fetch(:all, Bundler.feature_flag.cache_all? || nil)

      Bundler.settings.set_command_option_if_given :cache_all, all

      if Bundler.definition.has_local_dependencies? && !Bundler.feature_flag.cache_all?
        Bundler.ui.warn "Your Gemfile contains path and git dependencies. If you want "    \
          "to cache them as well, please pass the --all flag. This will be the default " \
          "on Bundler 3.0."
      end
    end
  end
end
