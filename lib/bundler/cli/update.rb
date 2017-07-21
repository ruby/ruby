# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Update
    attr_reader :options, :gems
    def initialize(options, gems)
      @options = options
      @gems = gems
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.feature_flag.plugins?

      sources = Array(options[:source])
      groups  = Array(options[:group]).map(&:to_sym)

      if gems.empty? && sources.empty? && groups.empty? && !options[:ruby] && !options[:bundler]
        # We're doing a full update
        Bundler.definition(true)
      else
        unless Bundler.default_lockfile.exist?
          raise GemfileLockNotFound, "This Bundle hasn't been installed yet. " \
            "Run `bundle install` to update and install the bundled gems."
        end
        Bundler::CLI::Common.ensure_all_gems_in_lockfile!(gems)

        if groups.any?
          specs = Bundler.definition.specs_for groups
          gems.concat(specs.map(&:name))
        end

        Bundler.definition(:gems => gems, :sources => sources, :ruby => options[:ruby],
                           :lock_shared_dependencies => options[:conservative])
      end

      Bundler::CLI::Common.configure_gem_version_promoter(Bundler.definition, options)

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      opts = options.dup
      opts["update"] = true
      opts["local"] = options[:local]

      Bundler.settings[:jobs] = opts["jobs"] if opts["jobs"]

      Bundler.definition.validate_runtime!
      installer = Installer.install Bundler.root, Bundler.definition, opts
      Bundler.load.cache if Bundler.app_cache.exist?

      if Bundler.settings[:clean] && Bundler.settings[:path]
        require "bundler/cli/clean"
        Bundler::CLI::Clean.new(options).run
      end

      Bundler.ui.confirm "Bundle updated!"
      Bundler::CLI::Common.output_without_groups_message
      Bundler::CLI::Common.output_post_install_messages installer.post_install_messages
    end
  end
end
