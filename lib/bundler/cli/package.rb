# frozen_string_literal: true
module Bundler
  class CLI::Package
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]
      Bundler.settings[:path] = File.expand_path(options[:path]) if options[:path]
      Bundler.settings[:cache_all_platforms] = options["all-platforms"] if options.key?("all-platforms")
      Bundler.settings[:cache_path] = options["cache-path"] if options.key?("cache-path")

      setup_cache_all
      install

      # TODO: move cache contents here now that all bundles are locked
      custom_path = Pathname.new(options[:path]) if options[:path]
      Bundler.load.cache(custom_path)
    end

  private

    def install
      require "bundler/cli/install"
      options = self.options.dup
      if Bundler.settings[:cache_all_platforms]
        options["local"] = false
        options["update"] = true
      end
      Bundler::CLI::Install.new(options).run
    end

    def setup_cache_all
      Bundler.settings[:cache_all] = options[:all] if options.key?("all")

      if Bundler.definition.has_local_dependencies? && !Bundler.settings[:cache_all]
        Bundler.ui.warn "Your Gemfile contains path and git dependencies. If you want "    \
          "to package them as well, please pass the --all flag. This will be the default " \
          "on Bundler 2.0."
      end
    end
  end
end
